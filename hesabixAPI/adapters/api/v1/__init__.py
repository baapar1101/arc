"""API v1 package.

Keep router exports lazy: importing a schema module must not import every API
router. Eager router imports can create cycles between API schemas and services
when background workers import a service directly.
"""

from importlib import import_module

_ROUTER_MODULES = {
    "health": "health",
    "categories": "categories",
    "products": "products",
    "price_lists": "price_lists",
    "invoices": "invoices",
}


def __getattr__(name: str):
    module_name = _ROUTER_MODULES.get(name)
    if module_name is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    router = import_module(f".{module_name}", __name__).router
    globals()[name] = router
    return router


__all__ = list(_ROUTER_MODULES)

