#!/usr/bin/env python3
"""
A stand-in for the two services SystemOne.Client talks to, to test the client
offline:

  POST /v1/systemone        the TypeSafe API (checks the request, returns a
                            canned response in the documented shape)
  POST /v1/chat/completions an OpenAI-compatible chat API (checks that a JSON
                            Schema is asked for, returns canned probabilities)
  GET  /_last               the last request body received, for assertions

It proves the CLIENT (request shape, parsing, normalization). It says nothing
about how Jev or a real LLM answers.

Usage: python fake_server.py [port]      (default 9099)
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LAST = {}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/_last":
            self._send(200, LAST)
        else:
            self._send(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        LAST.clear()
        LAST.update({"path": self.path, "auth": self.headers.get("Authorization"), "body": body})
        if self.headers.get("Authorization") not in ("Bearer good-key",):
            return self._send(401, {"error": "bad key"})

        if self.path == "/v1/systemone":
            qs = body.get("questions", {})
            if not body.get("state") or not body.get("model") or not qs:
                return self._send(400, {"error": "state, model and questions are required"})
            answers = {}
            for qid, q in qs.items():
                t = q.get("type")
                if t == "choice":
                    labels = list(q["criteria"].keys())
                    probs = {l: 0.05 for l in labels}
                    probs[labels[-1]] = 1 - 0.05 * (len(labels) - 1)
                    answers[qid] = {"type": "choice", "choice": labels[-1], "confidence": probs[labels[-1]],
                                    "probabilities": probs}
                elif t == "score":
                    n = len(q["criteria"])
                    probs = {str(i): 0.0 for i in range(n)}
                    probs["1"] = 0.8
                    probs["0"] = 0.2
                    answers[qid] = {"type": "score", "score": 1.24, "confidence": 0.8, "legend": q["criteria"],
                                    "probabilities": probs}
                elif t == "noul":
                    answers[qid] = {"type": "noul", "noul": 0.91}
                else:
                    return self._send(400, {"error": "unknown type " + str(t)})
            return self._send(200, {"model": "jev-1.13.0", "answers": answers,
                                    "usage": {"input_tokens": 42, "output_tokens": 0}})

        if self.path == "/v1/chat/completions":
            fmt = body.get("response_format", {})
            if fmt and fmt.get("type") == "json_schema":
                schema = fmt["json_schema"]["schema"]
                if "answers" not in schema.get("properties", {}):
                    return self._send(400, {"error": "schema without answers"})
            prompt = body["messages"][0]["content"]
            ans = {}
            # one canned answer per question id found in the prompt
            import re
            for m in re.finditer(r'- id "([^"]+)", type (\w+):', prompt):
                qid, t = m.group(1), m.group(2)
                if t == "noul":
                    ans[qid] = {"noul": 1.7}          # out of range on purpose: the client clamps it
                else:
                    opts = re.findall(r'option "([^"]+)":', prompt.split('id "%s"' % qid, 1)[1].split("\n- id", 1)[0])
                    # unnormalized on purpose: 6 and 2 -> 0.75 and 0.25; other options missing -> 0
                    probs = {opts[0]: 6, opts[1]: 2}
                    ans[qid] = {"probabilities": probs}
            content = json.dumps({"answers": ans})
            if "fence" in prompt:
                content = "```json\n" + content + "\n```"
            return self._send(200, {"choices": [{"message": {"role": "assistant", "content": content}}],
                                    "usage": {"prompt_tokens": 100, "completion_tokens": 20}})
        self._send(404, {})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9099
    HTTPServer(("127.0.0.1", port), H).serve_forever()
