"""Validate finished cards and store them. Text is not rewritten."""

from __future__ import annotations

from datetime import timedelta
from pathlib import Path
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

from proclan_server.categories import CATEGORIES, CategoryName
from proclan_server.net import is_public_url
from proclan_server.store import Card, Store, new_id, now

MAX_CARDS = 8
_TITLE = 40
_SUMMARY = 120
_BODY = 4000
_TAG = 12
_TAGS = 4
_SOURCE = 40
_BOT = 40
_BOT_DESC = 200
_SOURCE_URLS = 4
_IMAGES = 6

SUBMIT_CARDS_DOC = """提交已经写好的新闻卡片。填写以本工具当前 inputSchema 为准，不要沿用记忆里的字段。

一次 1 到 8 张。文本或原文链接不合格时，整批不入库。
服务不改写标题、摘要、正文、来源或分类。body 可以写 Markdown。
不要提交已读状态。非公网或不是 http(s) 的 image_urls 会丢掉，卡片仍入库。
"""


class CardRejected(Exception):
    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


def _hint() -> str:
    names = "、".join(CardIn.model_json_schema()["required"])
    return f"当前必填：{names}"


class CardIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=_TITLE, description=f"标题。必填，最多 {_TITLE} 字。")
    category: CategoryName = Field(description="分类。必填。只能是 " + "、".join(CATEGORIES) + "。")
    summary: str = Field(default="", max_length=_SUMMARY, description=f"摘要。可空，最多 {_SUMMARY} 字。")
    body: str = Field(
        default="",
        max_length=_BODY,
        description=(
            f"正文。可空，最多 {_BODY} 字。可以写 Markdown"
            "（标题、强调、列表、引用、代码、链接、表格、图片）。服务不改写。"
        ),
    )
    tags: list[Annotated[str, Field(max_length=_TAG)]] = Field(
        default_factory=list,
        max_length=_TAGS,
        description=f"标签。最多 {_TAGS} 个，每个最多 {_TAG} 字。空白的项会去掉。",
    )
    image_urls: list[str] = Field(
        default_factory=list,
        max_length=_IMAGES,
        description=f"配图地址。最多 {_IMAGES} 条。非公网或不是 http(s) 的图会丢掉，卡片仍入库。",
    )
    source_urls: list[str] = Field(
        default_factory=list,
        max_length=_SOURCE_URLS,
        description=f"原文链接。最多 {_SOURCE_URLS} 条公网 http(s)。",
    )
    source: str = Field(
        default="",
        max_length=_SOURCE,
        description=(
            f"消息来源，例如 Hacker News、Next.js Blog。刊物或站点名，不是 bot 名称。可空，最多 {_SOURCE} 字。"
        ),
    )
    created_bot: str = Field(
        min_length=1,
        max_length=_BOT,
        description=f"推送这张卡的 bot 名称。必填，最多 {_BOT} 字。不要写入 source。",
    )
    bot_desc: str = Field(
        min_length=1,
        max_length=_BOT_DESC,
        description=(
            f"这个 bot 的职责介绍。必填，最多 {_BOT_DESC} 字。"
            "写它负责盯什么、会推什么。不是这张卡的摘要，也不要写入 source。"
            "同一批里同一个名字出现多次时，用最后一条。"
        ),
    )

    @field_validator("tags", mode="before")
    @classmethod
    def _drop_blank_tags(cls, value: object) -> object:
        if not isinstance(value, list):
            return value
        kept: list[object] = []
        for item in value:
            if isinstance(item, str):
                text = item.strip()
                if text:
                    kept.append(text)
            else:
                kept.append(item)
        return kept

    @field_validator("source_urls", "image_urls", mode="before")
    @classmethod
    def _strip_urls(cls, value: object) -> object:
        if not isinstance(value, list):
            return value
        return [item.strip() if isinstance(item, str) else item for item in value]

    @field_validator("source_urls")
    @classmethod
    def _public_urls(cls, value: list[str]) -> list[str]:
        for position, url in enumerate(value, start=1):
            if not is_public_url(url):
                raise ValueError(f"第 {position} 条 source_urls 不是公网 http(s) 链接")
        return value

    @model_validator(mode="wrap")
    @classmethod
    def _explain(cls, value, handler):
        try:
            return handler(value)
        except ValidationError as exc:
            raise ValueError(_problem(exc)) from exc


def publish_cards(store: Store, media_dir: Path, cards: list[dict], *, user_id: str) -> list[str]:
    del media_dir  # kept so callers stay the same; new cards are not written to disk
    ready = _validate(cards)
    rows = _rows([(card, _public_images(card)) for card in ready])
    for row in rows:
        row.user_id = user_id
    store.insert_cards(rows)
    stamped = now().isoformat()
    for card, row in zip(ready, rows, strict=True):
        store.remember_bot(
            user_id,
            row.created_bot,
            created_at=stamped,
            bot_desc=card.bot_desc,
        )
    return [row.id for row in rows]


def _public_images(card: CardIn) -> list[str]:
    kept: list[str] = []
    for url in card.image_urls:
        if is_public_url(url) and url not in kept:
            kept.append(url)
    return kept


def _validate(cards: list[dict]) -> list[CardIn]:
    if not isinstance(cards, list) or not 1 <= len(cards) <= MAX_CARDS:
        raise CardRejected("一次提交 1 到 8 张卡")
    ready: list[CardIn] = []
    for index, raw in enumerate(cards, start=1):
        if not isinstance(raw, dict):
            raise CardRejected(f"第 {index} 张不是卡片。{_hint()}")
        try:
            ready.append(CardIn.model_validate(raw))
        except ValidationError as exc:
            raise _with_index(index, exc) from exc
    return ready


def _with_index(index: int, exc: ValidationError) -> CardRejected:
    message = exc.errors()[0]["msg"].removeprefix("Value error, ")
    if message.startswith("不是卡片"):
        text = f"第 {index} 张{message}"
    elif message.startswith("第 "):
        text = f"第 {index} 张的{message}"
    else:
        text = f"第 {index} 张的 {message}"
    return CardRejected(text)


def _problem(exc: ValidationError) -> str:
    err = exc.errors()[0]
    kind = err["type"]
    loc = err["loc"]
    field = str(loc[0]) if loc else "卡片"
    ctx = err.get("ctx") or {}
    if kind == "value_error":
        detail = err["msg"].removeprefix("Value error, ")
    elif kind == "extra_forbidden":
        detail = f"字段 {field} 不在 inputSchema 里"
    elif kind in {"missing", "string_too_short"}:
        detail = f"{field} 不能为空"
    elif kind == "string_too_long" and len(loc) == 1:
        detail = f"{field} 超过 {ctx.get('max_length')} 个字"
    elif kind == "string_too_long" and field == "tags":
        detail = f"第 {int(loc[1]) + 1} 个 tag 超过 {ctx.get('max_length')} 个字"
    elif kind == "string_too_long":
        detail = f"第 {int(loc[1]) + 1} 条 {field} 超过 {ctx.get('max_length')} 个字"
    elif kind == "too_long" and field == "tags":
        detail = f"tags 超过 {ctx.get('max_length')} 个"
    elif kind == "too_long":
        detail = f"{field} 超过 {ctx.get('max_length')} 条"
    elif kind == "literal_error":
        detail = "category 必须是：" + "、".join(CATEGORIES)
    elif kind == "list_type":
        detail = f"{field} 必须是列表"
    elif kind == "string_type" and len(loc) > 1 and field == "tags":
        detail = f"第 {int(loc[1]) + 1} 个 tag 必须是字符串"
    elif kind == "string_type" and len(loc) > 1:
        detail = f"第 {int(loc[1]) + 1} 条 {field} 必须是字符串"
    elif kind == "string_type":
        detail = f"{field} 必须是字符串"
    else:
        detail = "不是卡片" if not loc else f"{field} 不合格"
    return f"{detail}。{_hint()}"


def _rows(saved: list[tuple[CardIn, list[str]]]) -> list[Card]:
    base = now()
    rows: list[Card] = []
    total = len(saved)
    for index, (card, images) in enumerate(saved):
        rows.append(
            Card(
                id=new_id(),
                message_id="",
                title=card.title,
                summary=card.summary,
                body=card.body,
                category=card.category,
                tags=card.tags,
                images=images,
                source=card.source,
                source_urls=card.source_urls,
                created_bot=card.created_bot,
                processor="",
                is_read=False,
                created_at=(base + timedelta(microseconds=total - index)).isoformat(),
            )
        )
    return rows
