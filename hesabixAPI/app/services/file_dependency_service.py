from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import List, Optional
from uuid import UUID

from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.product import Product
from adapters.db.models.business import Business
from adapters.db.models.user import User


@dataclass
class FileDependency:
    module: str
    entity_type: str
    entity_id: str
    description: str

    def to_dict(self) -> dict:
        return asdict(self)


class FileDependencyService:
    """Utility service to discover and cleanup file dependencies across modules."""

    def __init__(self, db: Session):
        self.db = db

    def get_dependencies(self, file_storage: FileStorage) -> List[FileDependency]:
        ctx = (file_storage.module_context or "").lower()
        handler = getattr(self, f"_collect_{ctx}", None)
        if handler:
            dependencies = handler(file_storage)
        else:
            dependencies = []
            if file_storage.context_id:
                dependencies.append(
                    FileDependency(
                        module=file_storage.module_context or "unknown",
                        entity_type="context",
                        entity_id=str(file_storage.context_id),
                        description=f"Context ID {file_storage.context_id}",
                    )
                )
        return dependencies

    def cleanup_dependencies(self, file_storage: FileStorage) -> List[FileDependency]:
        """Remove references to file inside business entities. Returns dependencies removed for logging."""
        ctx = (file_storage.module_context or "").lower()
        handler = getattr(self, f"_cleanup_{ctx}", None)
        if handler:
            dependencies = handler(file_storage)
            if dependencies:
                self.db.commit()
            return dependencies
        return []

    # ---- Handlers ----

    def _collect_products(self, file_storage: FileStorage) -> List[FileDependency]:
        deps: List[FileDependency] = []
        product = self._get_product(file_storage)
        if product:
            deps.append(
                FileDependency(
                    module="products",
                    entity_type="product",
                    entity_id=str(product.id),
                    description=f"کالا: {product.name or product.code or product.id}",
                )
            )
        return deps

    def _cleanup_products(self, file_storage: FileStorage) -> List[FileDependency]:
        deps = self._collect_products(file_storage)
        product = self._get_product(file_storage)
        if product and product.image_file_id == str(file_storage.id):
            product.image_file_id = None
            self.db.flush()
        return deps

    def _collect_business_logo(self, file_storage: FileStorage) -> List[FileDependency]:
        deps: List[FileDependency] = []
        business = self._get_business(file_storage.business_id)
        if business and business.logo_file_id == str(file_storage.id):
            deps.append(
                FileDependency(
                    module="business_logo",
                    entity_type="business",
                    entity_id=str(business.id),
                    description=f"لوگوی کسب‌وکار: {business.name or business.id}",
                )
            )
        return deps

    def _cleanup_business_logo(self, file_storage: FileStorage) -> List[FileDependency]:
        deps = self._collect_business_logo(file_storage)
        business = self._get_business(file_storage.business_id)
        if business and business.logo_file_id == str(file_storage.id):
            business.logo_file_id = None
            self.db.flush()
        return deps

    def _collect_business_stamp(self, file_storage: FileStorage) -> List[FileDependency]:
        deps: List[FileDependency] = []
        business = self._get_business(file_storage.business_id)
        if business and business.stamp_file_id == str(file_storage.id):
            deps.append(
                FileDependency(
                    module="business_stamp",
                    entity_type="business",
                    entity_id=str(business.id),
                    description=f"مهر/امضای کسب‌وکار: {business.name or business.id}",
                )
            )
        return deps

    def _cleanup_business_stamp(self, file_storage: FileStorage) -> List[FileDependency]:
        deps = self._collect_business_stamp(file_storage)
        business = self._get_business(file_storage.business_id)
        if business and business.stamp_file_id == str(file_storage.id):
            business.stamp_file_id = None
            self.db.flush()
        return deps

    def _collect_user_signature(self, file_storage: FileStorage) -> List[FileDependency]:
        deps: List[FileDependency] = []
        user = self.db.query(User).filter(User.signature_file_id == str(file_storage.id)).first()
        if user:
            deps.append(
                FileDependency(
                    module="user_signature",
                    entity_type="user",
                    entity_id=str(user.id),
                    description=f"امضای کاربر: {user.full_name or user.username or user.id}",
                )
            )
        return deps

    def _cleanup_user_signature(self, file_storage: FileStorage) -> List[FileDependency]:
        deps = self._collect_user_signature(file_storage)
        user = self.db.query(User).filter(User.signature_file_id == str(file_storage.id)).first()
        if user:
            user.signature_file_id = None
            self.db.flush()
        return deps

    # ---- Helpers ----

    def _get_product(self, file_storage: FileStorage) -> Optional[Product]:
        query = self.db.query(Product)
        product_id: Optional[int] = None
        if file_storage.context_id:
            try:
                product_id = int(file_storage.context_id)
            except (TypeError, ValueError):
                product_id = None
        if product_id:
            query = query.filter(Product.id == product_id)
        else:
            query = query.filter(Product.image_file_id == str(file_storage.id))
        if file_storage.business_id:
            query = query.filter(Product.business_id == file_storage.business_id)
        return query.first()

    def _get_business(self, business_id: Optional[int]) -> Optional[Business]:
        if not business_id:
            return None
        return self.db.query(Business).filter(Business.id == business_id).first()

