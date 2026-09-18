import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def hello():
    return jsonify(
        message="Hello, World!",
        hostname=socket.gethostname(),  # handy for proving the Load Balancer is spreading traffic across pods
    )


@app.route("/healthz")
def healthz():
    # Used by Kubernetes liveness/readiness probes
    return jsonify(status="ok"), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
