"""Shared test setup: tests never reach real services."""

from __future__ import annotations

import socket

import httpx
import pytest


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    """Any attempt to look up a real host fails the test (Deezer and ntfy are always fakes)."""
    real = socket.getaddrinfo

    def guarded(host, *args, **kwargs):
        if host in ("localhost", "127.0.0.1", "::1"):
            return real(host, *args, **kwargs)
        raise AssertionError(f"Un test ha provato a contattare {host}: usa un servizio finto")

    monkeypatch.setattr(socket, "getaddrinfo", guarded)


def json_transport(routes: dict[str, object], log: list[httpx.Request] | None = None) -> httpx.MockTransport:
    """A fake server: ``routes`` maps a path (or path?query) to a JSON body, an
    ``httpx.Response`` or a list of them (one per call, in order)."""

    def handler(request: httpx.Request) -> httpx.Response:
        if log is not None:
            log.append(request)
        key = request.url.path + (f"?{request.url.query.decode()}" if request.url.query else "")
        answer = routes.get(key, routes.get(request.url.path))
        if answer is None:
            return httpx.Response(404, json={"error": f"route non prevista: {key}"})
        if isinstance(answer, list):
            answer = answer.pop(0)
        if isinstance(answer, httpx.Response):
            return answer
        return httpx.Response(200, json=answer)

    return httpx.MockTransport(handler)
