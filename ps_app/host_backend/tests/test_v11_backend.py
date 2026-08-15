from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ga3b_api import create_app
from ga3b_models import SearchResult
from ga3b_hifi_reference import replay_hifi
from ga3b_reference import score_trajectory, select_display_window
from ga3b_repository import ResultRepository
from ga3b_service import Ga3bBoardService, SearchRequest
from ga3b_uart_client import AgentResponse


RESULT_LINE = ("GA3B_RSP OK RESULT magic=0x52534C54 status=0x00000002 best_idx=0 "
               "fitness_hi=0x00000001 fitness_lo=0x00000010 steps=16 "
               "gene0=0x000037DA gene1=0x0000C2C4 gene2=0x00002ACF gene3=0xFFFF240C "
               "gene4=0x00013D51 gene5=0xFFFE13BE gene6=0xFFFF8FA0 gene7=0xFFFFD9EC")


class FakeService:
    def health(self):
        return {"status":"ok","board_connected":True,"accelerator_ready":True,"port":"MOCK",
                "profile_name":"pure3_hifi_leapfrog_cached",
                "hardware":{"profile_decimal":5}}
    def selftest(self):
        return {"status":"PASS","elapsed_ms":1,"result":SearchResult.from_uart_line(RESULT_LINE).to_dict()}
    def capabilities(self):
        return {"fitness_profiles":[{"id":"survival","recommended_candidates":1}],"limits":{}}
    def estimate_search(self, req, count):
        return {"candidate_count":count,"estimated_seconds":.1,"limit_seconds":30}
    def search(self, req, profile="survival", candidate_count=None):
        result=SearchResult.from_uart_line(RESULT_LINE).to_dict();result["trajectory"]=replay_hifi([int(x,16) for x in result["genes_raw"]],req.steps)
        return {"status":"PASS","elapsed_ms":2,"candidate_evals":req.candidate_evals,"candidate_evals_per_second":48000,"request":req.__dict__,"result":result}
    def benchmark(self, req, runs):
        return {"status":"PASS","probes":[],"hardware_runs":runs,
                "workload":{"max_gen":req.max_gen,"steps":req.steps,
                            "hardware_candidate_evals":req.candidate_evals,
                            "hardware_runs":runs}}
    def custom_replay(self, data):
        return Ga3bBoardService("MOCK").custom_replay(data)


def test_result_parser_and_q16():
    result = SearchResult.from_uart_line(RESULT_LINE)
    assert result.magic == 0x52534C54
    assert result.fitness == 0x0000000100000010
    decoded = result.to_dict()
    assert decoded["genes"][0] > 0
    assert decoded["genes"][3] < 0


def test_request_validation_and_candidate_count():
    request = SearchRequest.from_json({"max_gen":2,"steps":16,"seed0":"0x12345678"})
    assert request.candidate_evals == 96
    assert request.command().startswith("RUN 2 16")


def test_browser_percentages_decode_to_q16_and_saturate_100_percent():
    request = SearchRequest.from_json({
        "mutation_percent": 31.25, "crossover_percent": "87.50",
    })
    assert request.mutation_q16 == 20480
    assert request.crossover_q16 == 57344
    assert SearchRequest.from_json({"mutation_percent": 100}).mutation_q16 == 65535
    assert SearchRequest.from_json({"mutation_q16": 4096}).mutation_q16 == 4096


def test_api_and_static_page(tmp_path):
    app=create_app(FakeService(), ResultRepository(tmp_path / "page.sqlite3"));app.testing=True;client=app.test_client()
    assert client.get('/').status_code == 200
    assert client.get('/api/health').get_json()["board_connected"] is True
    response=client.post('/api/search',json={"max_gen":2,"steps":16})
    assert response.status_code == 200
    assert len(response.get_json()["result"]["trajectory"]["frames"]) == 17
    assert client.post('/api/search',json={"steps":0}).status_code == 400
    assert client.get('/api/capabilities').status_code == 200
    custom={"x0":.97,"y0":-.24,"vx0":.46,"vy0":.43,
            "x1":-.97,"y1":.24,"vx1":.46,"vy1":.43,"steps":64}
    replay=client.post('/api/custom-replay',json=custom)
    assert replay.status_code == 200
    assert replay.get_json()["execution_target"] == "pc_profile5_replay"
    assert "display_trajectory" in replay.get_json()


def test_four_physics_profiles_and_custom_limits():
    trajectory=replay_hifi([0x00010000,0,0,0,0xFFFF0000,0,0,0],32)
    for profile in ("survival","close_pass","braid","recurrence"):
        score,metrics=score_trajectory(profile,trajectory)
        assert isinstance(score,float)
        assert "recurrence_error" in metrics
    service=Ga3bBoardService("MOCK")
    try:
        service.custom_replay({"x0":3,"y0":0,"vx0":0,"vy0":0,
                               "x1":-1,"y1":0,"vx1":0,"vy1":0,"steps":16})
    except ValueError as exc:
        assert "[-2, 2]" in str(exc)
    else:
        raise AssertionError("out-of-range custom state was accepted")


def test_profile_search_reranks_multiple_hardware_results():
    lines=[
        RESULT_LINE,
        ("GA3B_RSP OK RESULT magic=0x52534C54 status=0x00000002 best_idx=1 "
         "fitness_hi=0x00000001 fitness_lo=0x00000020 steps=32 "
         "gene0=0x0000F852 gene1=0xFFFFC1C4 gene2=0x00007756 gene3=0x00006EAC "
         "gene4=0xFFFF07AE gene5=0x00003E3C gene6=0x00007756 gene7=0x00006EAC"),
    ]
    service=Ga3bBoardService("MOCK")
    calls=[]
    def fake_command(command,terminal=None):
        calls.append(command)
        return [AgentResponse(lines[(len(calls)-1)%len(lines)])]
    service._command=fake_command
    result=service.search(SearchRequest(max_gen=2,steps=32),"braid",2)
    assert result["candidate_count"] == 2
    assert len(calls) == 2
    assert "profile_match" in result["result"]


def test_event_highlight_window_is_continuous_and_preserves_absolute_steps():
    genes=[0x0000F852,0xFFFFC1C4,0x00007756,0x00006EAC,
           0xFFFF07AE,0x00003E3C,0x00007756,0x00006EAC]
    full=replay_hifi(genes,8192)
    highlight=select_display_window(full,"braid",120)
    assert highlight["display_frame_count"] <= 120
    assert highlight["window_start_step"] == highlight["frames"][0]["step"]
    assert highlight["window_end_step"] == highlight["frames"][-1]["step"]
    assert all(a["step"] < b["step"] for a,b in zip(highlight["frames"],highlight["frames"][1:]))
    # Selection is display-only: it must not rewrite the full trajectory result.
    assert full["requested_steps"] == 8192


def test_long_demo_profile_fits_extended_service_budget():
    service=Ga3bBoardService("MOCK")
    estimate=service.estimate_search(SearchRequest(max_gen=8,steps=8192),8)
    assert estimate["limit_seconds"] == 600
    assert estimate["estimated_seconds"] <= estimate["limit_seconds"]
    calibrated=service.estimate_search(SearchRequest(max_gen=64,steps=100000),8)
    assert 450 <= calibrated["estimated_seconds"] <= 500
    assert calibrated["calibration_reference_seconds"] == 457.332


def test_signed_seed_decimal_and_result_repository(tmp_path):
    request = SearchRequest.from_json({"seed0": -1, "seed1": -2023406815})
    assert request.seed0 == 0xFFFFFFFF
    assert request.seed1 == 0x87654321
    repository = ResultRepository(tmp_path / "results.sqlite3")
    record_id = repository.save("test", {"classification": {"id": "long_survival"},
                                         "result": {"steps": 22000}})
    assert repository.list()[0]["id"] == record_id
    assert repository.get(record_id)["result"]["steps"] == 22000


def test_presets_and_history_endpoints(tmp_path):
    repository = ResultRepository(tmp_path / "api.sqlite3")
    app = create_app(FakeService(), repository); app.testing = True
    client = app.test_client()
    presets = client.get('/api/presets').get_json()["presets"]
    assert {item["id"] for item in presets} == {
        "long_survival", "safe_close_pass", "three_body_braid", "near_recurrence"
    }
    response = client.post('/api/search', json={"max_gen": 2, "steps": 16})
    assert response.status_code == 200
    assert response.get_json()["record_id"] >= 1
    assert len(client.get('/api/results').get_json()["results"]) == 1


def test_performance_probe_is_bounded_for_interactive_ui(tmp_path):
    app = create_app(FakeService(), ResultRepository(tmp_path / "probe.sqlite3"))
    app.testing = True
    response = app.test_client().post('/api/performance/probe', json={
        "max_gen": 64, "steps": 65536, "hardware_runs": 99,
    })
    assert response.status_code == 200
    data = response.get_json()
    assert data["workload"]["max_gen"] == 8
    assert data["workload"]["steps"] == 8192
    assert data["workload"]["hardware_runs"] == 3
    assert data["probe_policy"]["bounded"] is True


def test_web_probe_and_data_tabs_are_wired():
    project = Path(__file__).resolve().parents[3]
    html = (project / "web/templates/index.html").read_text(encoding="utf-8-sig")
    javascript = (project / "web/static/app.js").read_text(encoding="utf-8")
    for element_id in ("runBenchmark", "probeStatus", "tabGenes", "tabMetrics",
                       "genes", "metricChips"):
        assert f'id="{element_id}"' in html
        assert f"$('{element_id}')" in javascript
    assert "showDataTab('genes')" in javascript
    assert "showDataTab('metrics')" in javascript
    assert "max_gen:8,steps:8192" in javascript
    assert 'id="mutation" type="number" min="0" max="100" step="0.01"' in html
    assert 'id="crossover" type="number" min="0" max="100" step="0.01"' in html
    assert "mutation_percent:decimal($('mutation').value)" in javascript
    assert "crossover_percent:decimal($('crossover').value)" in javascript
    assert "保守预计" in javascript
    assert "function setPlayback(playing)" in javascript
    assert "if(!app.playing){app.lastTick=t}" in javascript
    assert "$('playPause').onclick=()=>setPlayback(!app.playing)" in javascript
