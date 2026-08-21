"""Synthetic catalog scale benchmark — never registers into production."""
from __future__ import annotations

import json
import time
import tracemalloc
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List

from app.services.ai.ai_embedding_service import cosine_similarity
from app.services.ai.ai_tool_candidates import retrieve_candidates
from app.services.ai.ai_tool_embedding import hashed_ngram_vector
from app.services.ai.ai_tool_manifest import get_manifest_entry, iter_manifest_names
from app.services.ai.ai_tool_rank import score_tool_for_query
from app.services.ai.ai_tool_retrieval_index import ToolRetrievalIndex
from app.services.ai.ai_tool_schema import (
    SchemaSource,
    load_tool_schemas,
    reset_schema_cache_for_tests,
)

BENCH_DIR = Path("/opt/hesabix/app/docs/ai-agent/evals/tool-scale")
SIZES = (180, 500, 1200, 5000, 10000)
LARGE_SIZE = 100000
QUERY = "فاکتور فروش این ماه را پیدا کن"
STRESS_QPS = (1, 10, 50, 100)


class _FakeSchema(SchemaSource):
    def schema_version_for(self, name: str) -> str:
        return "1"

    def build_openai_tool_definition(self, name: str):
        return {
            "type": "function",
            "function": {
                "name": name,
                "description": f"synthetic or real tool {name}",
                "parameters": {"type": "object", "properties": {}},
            },
        }


def _catalog(size: int) -> List[str]:
    real = list(iter_manifest_names())
    if size <= len(real):
        return real[:size]
    extra = [f"synth_tool_{i:05d}" for i in range(size - len(real))]
    return real + extra


def _search_text(name: str) -> str:
    entry = get_manifest_entry(name)
    if entry is not None:
        return entry.search_text(name, "")
    try:
        n = int(name.rsplit("_", 1)[-1])
    except ValueError:
        n = 1
    if n % 47 == 0:
        return f"{name} invoice فاکتور فروش"
    return f"{name} synthetic warehouse crm report search list"


def _build_index(names: List[str]) -> ToolRetrievalIndex:
    index = ToolRetrievalIndex()
    docs = []
    for name in names:
        extra = "" if get_manifest_entry(name) is not None else _search_text(name)
        docs.append((name, extra))
    index.load_many(docs)
    return index


def _percentile(values: List[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = int(round((p / 100.0) * (len(ordered) - 1)))
    idx = max(0, min(len(ordered) - 1, idx))
    return ordered[idx]


def _bench_size(
    size: int,
    *,
    include_semantic: bool = True,
    include_linear: bool = True,
) -> Dict[str, Any]:
    names = _catalog(size)
    index = _build_index(names)
    stats = index.stats()

    lex_ms = None
    ranked: List[str] = []
    if include_linear:
        t0 = time.perf_counter()
        lex = {n: score_tool_for_query(n, QUERY) for n in names}
        lex_ms = round((time.perf_counter() - t0) * 1000.0, 3)
        ranked = sorted(lex, key=lambda n: (-lex[n], n))[:15]

    query_latencies = []
    for _ in range(12):
        offer = retrieve_candidates(
            QUERY,
            names,
            n=100,
            fallback_on_empty=False,
            include_vector=False,
            index=index,
            expects_tools=True,
        )
        query_latencies.append(offer.latency_ms)
    inv_ms = round(sum(query_latencies) / len(query_latencies), 3)

    sem_ms = None
    if include_semantic:
        vectors = {n: hashed_ngram_vector(_search_text(n)) for n in names}
        qvec = hashed_ngram_vector(QUERY)
        t1 = time.perf_counter()
        sem = []
        for n, vec in vectors.items():
            s = cosine_similarity(qvec, vec)
            if s > 0.02:
                sem.append((n, s))
        sem.sort(key=lambda item: -item[1])
        sem_ms = round((time.perf_counter() - t1) * 1000.0, 3)

    schema_ms = None
    if ranked:
        reset_schema_cache_for_tests()
        t2 = time.perf_counter()
        load_tool_schemas(
            ranked,
            authorized_names=set(ranked),
            source=_FakeSchema(),
        )
        schema_ms = round((time.perf_counter() - t2) * 1000.0, 3)

    return {
        "size": size,
        "real_tools": min(size, len(iter_manifest_names())),
        "synthetic_tools": max(0, size - len(iter_manifest_names())),
        "keyword_linear_ms": lex_ms,
        "inverted_index_build_ms": stats.build_ms,
        "inverted_index_query_ms": inv_ms,
        "inverted_index_query_p50_ms": round(_percentile(query_latencies, 50), 3),
        "inverted_index_query_p95_ms": round(_percentile(query_latencies, 95), 3),
        "inverted_postings": stats.postings,
        "index_memory_bytes_est": stats.memory_bytes_est,
        "semantic_linear_ms": sem_ms,
        "ranking_latency_ms": lex_ms,
        "semantic_search_latency_ms": sem_ms,
        "discovery_latency_ms": round((lex_ms or 0) + (sem_ms or 0), 3),
        "schema_loading_latency_ms": schema_ms,
        "database_queries": 0,
        "top15": ranked[:5],
        "inverted_top15": list(offer.names[:5]),
        "production_ready": False,
    }


def _stress(index: ToolRetrievalIndex, names: List[str], workers: int) -> Dict[str, Any]:
    latencies: List[float] = []

    def _one() -> float:
        offer = retrieve_candidates(
            QUERY,
            names,
            n=100,
            fallback_on_empty=False,
            include_vector=False,
            index=index,
            expects_tools=True,
        )
        return offer.latency_ms

    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futs = [pool.submit(_one) for _ in range(max(workers, 1))]
        for fut in as_completed(futs):
            latencies.append(fut.result())
    wall = round((time.perf_counter() - started) * 1000.0, 3)
    return {
        "concurrency": workers,
        "queries": len(latencies),
        "wall_ms": wall,
        "p50_ms": round(_percentile(latencies, 50), 3),
        "p95_ms": round(_percentile(latencies, 95), 3),
    }


def run_scale_benchmark(*, write_files: bool = False) -> Dict[str, Any]:
    tracemalloc.start()
    rows = [_bench_size(size) for size in SIZES]
    large = _bench_size(LARGE_SIZE, include_semantic=False, include_linear=False)
    names_10k = _catalog(10000)
    index_10k = _build_index(names_10k)
    stress = [_stress(index_10k, names_10k, qps) for qps in STRESS_QPS]
    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    ten_k = next((row for row in rows if row["size"] == 10000), {})
    report = {
        "sizes": rows,
        "size_100000": large,
        "stress_10k": stress,
        "memory_current_kb": round(current / 1024, 1),
        "memory_peak_kb": round(peak / 1024, 1),
        "note": (
            "Synthetic names never enter production registry. "
            "Inverted index is derived posting lists. "
            "Linear semantic at 10k is not a production design. "
            "100k skips semantic scan."
        ),
        "index_study": {
            "A_inverted_keyword": "In-process inverted index is the Phase 10 candidate generator.",
            "B_postgres_gin_trigram": "Optional later for fuzzy tokens; not required at 10k.",
            "C_pgvector_ann": "Existing pgvector is for knowledge chunks, not tools. No new vector DB.",
            "D_hnsw": "Preferred future ANN when a versioned neural embedding exists.",
            "E_hybrid_inverted_plus_vector": "Merge is implemented behind VECTOR_CANDIDATE_RETRIEVAL=False.",
            "phase_10_gate": "Do not ship 10k linear semantic. Keyword inverted index is the online path.",
            "semantic_10k_ms": ten_k.get("semantic_linear_ms"),
            "inverted_10k_query_ms": ten_k.get("inverted_index_query_ms"),
            "keyword_10k_ms": ten_k.get("keyword_linear_ms"),
        },
    }
    if write_files:
        BENCH_DIR.mkdir(parents=True, exist_ok=True)
        (BENCH_DIR / "latest.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return report


def main() -> None:
    report = run_scale_benchmark(write_files=True)
    summary = {
        "sizes": [
            {
                "size": row["size"],
                "inverted_ms": row["inverted_index_query_ms"],
                "keyword_ms": row["keyword_linear_ms"],
                "semantic_ms": row["semantic_linear_ms"],
                "build_ms": row["inverted_index_build_ms"],
            }
            for row in report["sizes"]
        ],
        "size_100000_inverted_ms": report["size_100000"]["inverted_index_query_ms"],
        "stress_10k": report["stress_10k"],
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
