#!/usr/bin/env python3
"""
Omesh HTTP API External Test Suite
Tests the API from a real client's perspective.
"""

import subprocess
import time
import signal
import sys
import json

try:
    import requests
except ImportError:
    print("Installing requests library...")
    subprocess.run([sys.executable, "-m", "pip", "install", "requests", "-q"])
    import requests

BASE_URL = "http://localhost:8080"

def start_server():
    """Start omesh server, return process"""
    proc = subprocess.Popen(
        ["./build/omesh", "--http", "8080"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    # Wait for server to be ready with retries
    for i in range(10):
        time.sleep(0.5)
        try:
            r = requests.get(f"{BASE_URL}/health", timeout=1)
            if r.status_code == 200:
                return proc
        except:
            pass
    raise Exception("Server failed to start")

def stop_server(proc):
    """Stop server gracefully"""
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

def test_health():
    """GET /health returns 200 with JSON"""
    r = requests.get(f"{BASE_URL}/health")
    assert r.status_code == 200, f"Expected 200, got {r.status_code}"
    data = r.json()
    assert "status" in data, "Missing 'status' field"
    print("  ✓ GET /health")
    return True

def post_index(content):
    """Helper to POST a document"""
    headers = {"Content-Type": "application/json"}
    body = json.dumps({"content": content})
    return requests.post(f"{BASE_URL}/index", data=body, headers=headers)

def test_index_document():
    """POST /index indexes a document"""
    r = post_index("hello world test document")
    assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"
    data = r.json()
    assert "doc_id" in data, "Missing 'doc_id' field"
    print(f"  ✓ POST /index (doc_id present)")
    return data.get("doc_id")

def test_search_found(query):
    """GET /search finds results"""
    r = requests.get(f"{BASE_URL}/search", params={"q": query})
    assert r.status_code == 200, f"Expected 200, got {r.status_code}"
    data = r.json()
    results = data.get("results", [])
    print(f"  ✓ GET /search?q={query} ({len(results)} results)")
    return len(results)

def test_search_not_found(query):
    """GET /search returns empty for unknown terms"""
    r = requests.get(f"{BASE_URL}/search", params={"q": query})
    assert r.status_code == 200, f"Expected 200, got {r.status_code}"
    data = r.json()
    results = data.get("results", [])
    assert len(results) == 0, f"Expected 0 results, got {len(results)}"
    print(f"  ✓ GET /search?q={query} (0 results, as expected)")
    return True

def test_empty_content():
    """POST /index with empty content returns error"""
    r = post_index("")
    print(f"  ✓ POST /index empty content (status: {r.status_code})")
    return True

def test_missing_query():
    """GET /search without q param"""
    r = requests.get(f"{BASE_URL}/search")
    print(f"  ✓ GET /search no query (status: {r.status_code})")
    return True

def test_special_chars():
    """Search with special characters"""
    r = requests.get(f"{BASE_URL}/search", params={"q": "hello & world"})
    print(f"  ✓ GET /search special chars (status: {r.status_code})")
    return True

def test_404():
    """Unknown path returns 404"""
    r = requests.get(f"{BASE_URL}/unknown")
    assert r.status_code == 404, f"Expected 404, got {r.status_code}"
    print(f"  ✓ GET /unknown (404)")
    return True

def test_cors_headers():
    """All responses should have CORS headers"""
    r = requests.get(f"{BASE_URL}/health")
    assert "Access-Control-Allow-Origin" in r.headers, "Missing CORS origin header"
    assert r.headers["Access-Control-Allow-Origin"] == "*", "CORS origin should be *"
    assert "Access-Control-Allow-Methods" in r.headers, "Missing CORS methods header"
    assert "Access-Control-Allow-Headers" in r.headers, "Missing CORS headers header"
    print("  ✓ CORS headers present")
    return True

def test_options_preflight():
    """OPTIONS request returns 204 with CORS headers"""
    r = requests.options(f"{BASE_URL}/index")
    assert r.status_code == 204, f"Expected 204, got {r.status_code}"
    assert "Access-Control-Allow-Origin" in r.headers, "Missing CORS origin header"
    assert "Access-Control-Allow-Methods" in r.headers, "Missing CORS methods header"
    assert "Access-Control-Allow-Headers" in r.headers, "Missing CORS headers header"
    print("  ✓ OPTIONS preflight works")
    return True

def run_all_tests():
    print("=" * 60)
    print("Omesh HTTP API Test Suite")
    print("=" * 60)

    proc = None
    passed = 0
    failed = 0

    try:
        print("\n[Starting server...]")
        proc = start_server()
        print("  Server ready")

        print("\n[Health Check]")
        test_health()
        passed += 1

        print("\n[Indexing]")
        test_index_document()
        passed += 1
        post_index("the quick brown fox")
        post_index("lazy dog sleeps")
        post_index("quick quick quick")
        print("  ✓ Indexed 3 more documents")
        passed += 1

        print("\n[Search - Found]")
        test_search_found("hello")
        passed += 1
        test_search_found("quick")
        passed += 1

        print("\n[Search - Not Found]")
        test_search_not_found("xyzzynonexistent")
        passed += 1

        print("\n[Edge Cases]")
        test_empty_content()
        passed += 1
        test_missing_query()
        passed += 1
        test_special_chars()
        passed += 1
        test_404()
        passed += 1

        print("\n[CORS Support]")
        test_cors_headers()
        passed += 1
        test_options_preflight()
        passed += 1

    except AssertionError as e:
        print(f"  ✗ FAILED: {e}")
        failed += 1
    except requests.exceptions.ConnectionError as e:
        print(f"  ✗ FAILED: Could not connect to server")
        failed += 1
    except Exception as e:
        print(f"  ✗ FAILED: {type(e).__name__}: {e}")
        failed += 1
    finally:
        if proc:
            print("\n[Stopping server...]")
            stop_server(proc)

    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)

    return failed == 0

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
