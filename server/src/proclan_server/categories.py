"""The only categories a card is allowed to carry."""

from typing import Literal, get_args

CategoryName = Literal["科技", "财经", "国际", "社会", "生活", "其他"]
CATEGORIES: tuple[str, ...] = get_args(CategoryName)
OTHER = "其他"


def normalize_category(value: str | None) -> str:
    if value in CATEGORIES:
        return value
    return OTHER
