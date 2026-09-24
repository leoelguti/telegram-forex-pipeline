"""The module responsible for operating tgcf in live mode."""

import logging
import os
import re
import sys
from typing import Union

from telethon import TelegramClient, events, functions, types
from telethon.sessions import StringSession
from telethon.tl.custom.message import Message

from tgcf import config, const
from tgcf import storage as st
from tgcf.bot import get_events
from tgcf.config import CONFIG, get_SESSION
from tgcf.plugins import apply_plugins, load_async_plugins
from tgcf.utils import clean_session_files, send_message


async def get_origin_metadata(event, chat_id: int):
    """Obtain clean origin channel ID and name for pipeline attribution."""
    channel_id = str(chat_id)
    channel_name = ""

    try:
        chat = getattr(event, "chat", None)
        if not chat and hasattr(event, "get_chat"):
            chat = await event.get_chat()
        if chat:
            channel_name = getattr(chat, "title", None) or getattr(chat, "username", None) or ""
    except Exception as err:
        logging.debug(f"Could not resolve entity for {chat_id}: {err}")

    if not channel_name and hasattr(config, "CONFIG") and config.CONFIG.forwards:
        for fwd in config.CONFIG.forwards:
            f_src = str(fwd.source).strip()
            if f_src == channel_id or f_src in channel_id or channel_id in f_src:
                if fwd.con_name:
                    clean = fwd.con_name.split(" a ")[0].split(" -> ")[0].strip()
                    channel_name = clean
                break

    if channel_name:
        channel_name = re.sub(r"[\[\]\|\r\n]", "", str(channel_name)).strip()
    else:
        channel_name = f"Channel_{channel_id}"

    return channel_id, channel_name


SPAM_PATTERNS = [
    r"\bjoin\s+vip\b",
    r"\bvip\s+(?:access|channel|group|discount|promo|lifetime)\b",
    r"\bdiscount\s+\d+%",
    r"\bcontact\s+@\w+",
    r"\bmessage\s+(?:admin|me)\b",
    r"\bpass\s+prop\s*firm\b",
    r"\baccount\s+management\b",
    r"\bguaranteed\s+(?:profit|return|income)\b",
    r"\binvest\s+with\s+me\b",
    r"\bcrypto\s+pump\b",
    r"\bhft\s+(?:bot|ea|algo)\b",
    r"\bspecial\s+offer\b",
    r"\blifetime\s+(?:membership|access)\b",
    r"\bfree\s+trial\s+ends\b",
    r"\bgiveaway\b",
    r"\bpromo\s+code\b",
    r"\bdeposit\s+bonus\b",
]

TRADING_PATTERNS = [
    r"\b(buy|sell|compra|comprar|venta|vender|long|short)\b",
    r"\b(xauusd|gold|eurusd|gbpusd|usdjpy|usdcad|audusd|nzdusd|usdchf|eurjpy|gbpjpy|us30|nas100|ustec|spx500|ger30|ger40|dax|oil|wti|usousd)\b",
    r"\b(sl|stop\s*loss|tp\d*|take\s*profit\d*|target\d*|entry|entrada|breakeven|be)\b",
    r"\b(running\s+\+\d+\s*pips|close\s+half|secure\s+profit|partial\s+close)\b",
]


def is_spam_message(text: str) -> bool:
    """Return True if message matches spam patterns and does not contain genuine trading orders."""
    if not text:
        return False
    lower = text.lower()
    has_spam = any(re.search(pat, lower) for pat in SPAM_PATTERNS)
    if not has_spam:
        return False
    # If it has marketing text but also clearly contains a trading order with SL, do not discard
    has_trade_action = bool(re.search(r"\b(buy|sell|long|short|compra|venta)\b", lower))
    has_sl = bool(re.search(r"\b(sl|stop\s*loss)\b", lower))
    if has_trade_action and has_sl:
        return False
    return True


def is_trading_related(text: str) -> bool:
    """Return True if message contains trading signal or market update terms."""
    if not text:
        return False
    lower = text.lower()
    return any(re.search(pat, lower) for pat in TRADING_PATTERNS)


async def new_message_handler(event: Union[Message, events.NewMessage]) -> None:
    """Process new incoming messages."""
    chat_id = event.chat_id

    if chat_id not in config.from_to:
        return
    logging.info(f"New message received in {chat_id}")
    message = event.message

    event_uid = st.EventUid(event)

    length = len(st.stored)
    exceeding = length - const.KEEP_LAST_MANY

    if exceeding > 0:
        for key in st.stored:
            del st.stored[key]
            break

    dest = config.from_to.get(chat_id)

    tm = await apply_plugins(message)
    if not tm:
        return

    # Check anti-spam and trading filters
    live_cfg = getattr(config.CONFIG, "live", None)
    filter_spam = getattr(live_cfg, "filter_spam", True)
    only_signals = getattr(live_cfg, "only_trading_signals", False)
    raw_text = tm.text or ""

    if filter_spam and is_spam_message(raw_text):
        logging.info(f"🚫 [ANTI-SPAM] Mensaje de {chat_id} filtrado por publicidad/spam: {raw_text[:60]}...")
        tm.clear()
        return

    if only_signals and not is_trading_related(raw_text):
        logging.info(f"⏭️ [SMART-FILTER] Mensaje de {chat_id} ignorado (sin terminos de trading): {raw_text[:60]}...")
        tm.clear()
        return

    # Append origin channel metadata for downstream processing (n8n, PocketBase, MT5)
    cid, cname = await get_origin_metadata(event, chat_id)
    origin_tag = f"\n\n[ORIGIN_ID:{cid}|NAME:{cname}]"
    curr_text = tm.text or ""
    if "[ORIGIN_ID:" not in curr_text:
        tm.text = (curr_text.strip() + origin_tag).strip()

    if event.is_reply:
        r_event = st.DummyEvent(chat_id, event.reply_to_msg_id)
        r_event_uid = st.EventUid(r_event)

    st.stored[event_uid] = {}
    for d in dest:
        if event.is_reply and r_event_uid in st.stored:
            tm.reply_to = st.stored.get(r_event_uid).get(d)
        fwded_msg = await send_message(d, tm)
        st.stored[event_uid].update({d: fwded_msg})
    tm.clear()


async def edited_message_handler(event) -> None:
    """Handle message edits."""
    message = event.message

    chat_id = event.chat_id

    if chat_id not in config.from_to:
        return

    logging.info(f"Message edited in {chat_id}")

    event_uid = st.EventUid(event)

    tm = await apply_plugins(message)

    if not tm:
        return

    # Check anti-spam and trading filters on edit
    edit_raw_text = tm.text or ""
    if filter_spam and is_spam_message(edit_raw_text):
        logging.info(f"🚫 [ANTI-SPAM] Mensaje editado de {chat_id} filtrado por publicidad/spam: {edit_raw_text[:60]}...")
        tm.clear()
        return

    if only_signals and not is_trading_related(edit_raw_text):
        logging.info(f"⏭️ [SMART-FILTER] Mensaje editado de {chat_id} ignorado (sin terminos de trading): {edit_raw_text[:60]}...")
        tm.clear()
        return

    # Append origin channel metadata
    cid, cname = await get_origin_metadata(event, chat_id)
    origin_tag = f"\n\n[ORIGIN_ID:{cid}|NAME:{cname}]"
    curr_text = tm.text or ""
    if "[ORIGIN_ID:" not in curr_text:
        tm.text = (curr_text.strip() + origin_tag).strip()

    fwded_msgs = st.stored.get(event_uid)

    if fwded_msgs:
        for _, msg in fwded_msgs.items():
            if config.CONFIG.live.delete_on_edit == message.text:
                await msg.delete()
                await message.delete()
            else:
                await msg.edit(tm.text)
        return

    dest = config.from_to.get(chat_id)

    for d in dest:
        await send_message(d, tm)
    tm.clear()


async def deleted_message_handler(event):
    """Handle message deletes."""
    chat_id = event.chat_id
    if chat_id not in config.from_to:
        return

    logging.info(f"Message deleted in {chat_id}")

    event_uid = st.EventUid(event)
    fwded_msgs = st.stored.get(event_uid)
    if fwded_msgs:
        for _, msg in fwded_msgs.items():
            await msg.delete()
        return


ALL_EVENTS = {
    "new": (new_message_handler, events.NewMessage()),
    "edited": (edited_message_handler, events.MessageEdited()),
    "deleted": (deleted_message_handler, events.MessageDeleted()),
}


async def start_sync() -> None:
    """Start tgcf live sync."""
    # clear past session files
    clean_session_files()

    # load async plugins defined in plugin_models
    await load_async_plugins()

    SESSION = get_SESSION()
    client = TelegramClient(
        SESSION,
        CONFIG.login.API_ID,
        CONFIG.login.API_HASH,
        sequential_updates=CONFIG.live.sequential_updates,
    )
    if CONFIG.login.user_type == 0:
        if CONFIG.login.BOT_TOKEN == "":
            logging.warning("Bot token not found, but login type is set to bot.")
            sys.exit()
        await client.start(bot_token=CONFIG.login.BOT_TOKEN)
    else:
        await client.start()
    config.is_bot = await client.is_bot()
    logging.info(f"config.is_bot={config.is_bot}")
    command_events = get_events()

    await config.load_admins(client)

    ALL_EVENTS.update(command_events)

    for key, val in ALL_EVENTS.items():
        if config.CONFIG.live.delete_sync is False and key == "deleted":
            continue
        client.add_event_handler(*val)
        logging.info(f"Added event handler for {key}")

    if config.is_bot and const.REGISTER_COMMANDS:
        await client(
            functions.bots.SetBotCommandsRequest(
                scope=types.BotCommandScopeDefault(),
                lang_code="en",
                commands=[
                    types.BotCommand(command=key, description=value)
                    for key, value in const.COMMANDS.items()
                ],
            )
        )
    config.from_to = await config.load_from_to(client, config.CONFIG.forwards)
    await client.run_until_disconnected()
