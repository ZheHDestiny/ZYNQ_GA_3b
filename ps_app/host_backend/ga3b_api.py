"""GA3B v1.1 HTTP backend and static web host."""

from __future__ import annotations

import argparse
import atexit
import json
import logging
from pathlib import Path
import threading
import webbrowser

from flask import Flask, jsonify, render_template, request

from ga3b_service import Ga3bBoardService, SearchRequest
from ga3b_repository import ResultRepository


ROOT = Path(__file__).resolve().parents[2]
WEB_ROOT = ROOT / "web"


def create_app(board_service=None, repository=None) -> Flask:
    app = Flask(__name__, template_folder=str(WEB_ROOT / "templates"),
                static_folder=str(WEB_ROOT / "static"), static_url_path="/static")
    service = board_service or Ga3bBoardService("COM13")
    result_store = repository or ResultRepository(ROOT / "doc" / "test_results" / "ga3b_results.sqlite3")
    preset_path = ROOT / "ps_app" / "host_backend" / "presets" / "trajectory_templates.json"
    presets = json.loads(preset_path.read_text(encoding="utf-8"))
    app.config["GA3B_SERVICE"] = service

    @app.after_request
    def no_cache(response):
        if request.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    @app.errorhandler(ValueError)
    def bad_request(exc):
        return jsonify({"status": "error", "error": str(exc)}), 400

    @app.errorhandler(Exception)
    def server_error(exc):
        app.logger.exception("request failed")
        return jsonify({"status": "error", "error": str(exc)}), 503

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        result = service.health()
        return jsonify(result), 200 if result.get("board_connected") else 503

    @app.get("/api/capabilities")
    def capabilities():
        return jsonify(service.capabilities())

    @app.post("/api/selftest")
    def selftest():
        return jsonify(service.selftest())

    @app.post("/api/search")
    def search():
        data = request.get_json(silent=True) or {}
        profile = str(data.get("fitness_profile", "survival"))
        candidate_count = data.get("candidate_count")
        if candidate_count is not None:
            candidate_count = int(candidate_count)
        result = service.search(SearchRequest.from_json(data), profile, candidate_count)
        result["record_id"] = result_store.save("fpga_search", result)
        return jsonify(result)

    @app.post("/api/estimate")
    def estimate():
        data = request.get_json(silent=True) or {}
        profile = str(data.get("fitness_profile", "survival"))
        profiles = {item["id"]: item for item in service.capabilities()["fitness_profiles"]}
        if profile not in profiles:
            raise ValueError(f"unknown fitness_profile: {profile}")
        count = int(data.get("candidate_count", profiles[profile]["recommended_candidates"]))
        return jsonify(service.estimate_search(SearchRequest.from_json(data), count))

    @app.post("/api/custom-replay")
    def custom_replay():
        result = service.custom_replay(request.get_json(silent=True) or {})
        result["record_id"] = result_store.save("pc_replay", result)
        return jsonify(result)

    @app.get("/api/results")
    def list_results():
        return jsonify({"status": "ok", "results": result_store.list(request.args.get("limit", 20))})

    @app.get("/api/results/<int:result_id>")
    def get_result(result_id: int):
        result = result_store.get(result_id)
        if result is None:
            return jsonify({"status": "error", "error": "result not found"}), 404
        return jsonify(result)

    @app.get("/api/presets")
    def list_presets():
        return jsonify({"status": "ok", "presets": presets})

    @app.post("/api/presets/<preset_id>/run")
    def run_preset(preset_id: str):
        preset = next((item for item in presets if item["id"] == preset_id), None)
        if preset is None:
            raise ValueError("unknown trajectory preset")
        result = service.search(SearchRequest.from_json(preset), preset["fitness_profile"], 1)
        result["preset"] = {"id": preset["id"], "name": preset["name"],
                            "expected_category": preset["expected_category"]}
        result["record_id"] = result_store.save("fpga_preset", result)
        return jsonify(result)

    @app.post("/api/performance/probe")
    def performance_probe():
        data = request.get_json(silent=True) or {}
        requested = SearchRequest.from_json(data)
        # Keep the interactive comparison bounded but large enough to expose
        # accelerator throughput over scalar/runtime software proxies.
        search_request = SearchRequest(
            max_gen=min(requested.max_gen, 8),
            steps=min(requested.steps, 8192),
            mutation_q16=requested.mutation_q16,
            crossover_q16=requested.crossover_q16,
            seed0=requested.seed0,
            seed1=requested.seed1,
        )
        runs = min(3, max(1, int(data.get("hardware_runs", 2))))
        result = service.benchmark(search_request, runs)
        result["probe_policy"] = {
            "max_gen": 8, "steps": 8192, "hardware_runs": runs,
            "requested_max_gen": requested.max_gen,
            "requested_steps": requested.steps,
            "bounded": (requested.max_gen != search_request.max_gen or
                        requested.steps != search_request.steps),
        }
        return jsonify(result)

    return app


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="COM13", help="board UART port")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--http-port", type=int, default=8000)
    parser.add_argument("--uart-timeout", type=float, default=60.0)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--open-browser", action="store_true")
    args = parser.parse_args()
    service = Ga3bBoardService(args.port, timeout=args.uart_timeout)
    atexit.register(service.close)
    app = create_app(service)
    logging.getLogger("werkzeug").setLevel(logging.INFO)
    print(f"GA3B_WEB_READY http://{args.host}:{args.http_port} UART={args.port}", flush=True)
    if args.open_browser:
        threading.Timer(1.0, webbrowser.open,
                        args=(f"http://{args.host}:{args.http_port}/",)).start()
    app.run(host=args.host, port=args.http_port, debug=args.debug, threaded=True,
            use_reloader=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
