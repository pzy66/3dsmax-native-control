"""Run inside 3ds Max with python.ExecuteFile, never with standalone Python."""
import json
import os
from pathlib import Path

from pymxs import runtime as rt


def safe_text(value):
    try:
        return str(value)
    except Exception as exc:
        return f"<unavailable: {exc}>"


def probe():
    renderer = rt.renderers.current
    nodes = []
    for node in rt.objects:
        nodes.append({
            "name": str(node.name),
            "class": safe_text(rt.classOf(node)),
            "parent": str(node.parent.name) if node.parent else None,
            "material": str(node.material.name) if node.material else None,
        })
    report = {
        "pid": os.getpid(),
        "max_version": safe_text(rt.maxVersion()),
        "scene_file": str(rt.maxFilePath) + str(rt.maxFileName),
        "save_required": bool(rt.getSaveRequired()),
        "plugcfg": str(rt.getDir(rt.Name("plugcfg"))),
        "renderer_class": safe_text(rt.classOf(renderer)),
        "renderer_properties": [str(prop) for prop in rt.getPropNames(renderer)],
        "corona_physical_material_available": getattr(rt, "CoronaPhysicalMtl", None) is not None,
        "step_importer_available": getattr(rt, "ATF_STEP_importer", None) is not None,
        "node_count": len(nodes),
        "nodes": nodes,
    }
    output = Path(__file__).resolve().parent / "probe.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


probe()
