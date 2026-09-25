"""Utility functions to smoothen your life."""

import logging
import os
import platform
import re
import sys
from datetime import datetime
from typing import TYPE_CHECKING

from telethon.client import TelegramClient
from telethon.hints import EntityLike
from telethon.tl.custom.message import Message

from tgcf import __version__
from tgcf.config import CONFIG
from tgcf.plugin_models import STYLE_CODES

if TYPE_CHECKING:
    from tgcf.plugins import TgcfMessage


def platform_info():
    nl = "\n"
    return f"""Running tgcf {__version__}\
    \nPython {sys.version.replace(nl,"")}\
    \nOS {os.name}\
    \nPlatform {platform.system()} {platform.release()}\
    \n{platform.architecture()} {platform.processor()}"""


MAX_CAPTION_LEN = 1024


async def send_message(recipient: EntityLike, tm: "TgcfMessage") -> Message:
    """Forward or send a copy, depending on config."""
    client: TelegramClient = tm.client
    if CONFIG.show_forwarded_from:
        return await client.forward_messages(recipient, tm.message)

    caption_text = tm.text or ""
    has_media = bool(tm.message and getattr(tm.message, "media", None))

    # Telegram non-premium caption limit for media is 1024 characters
    if has_media and len(caption_text) > MAX_CAPTION_LEN:
        origin_match = re.search(r"(\n\n\[ORIGIN_ID:[^\]]+\])$", caption_text)
        origin_tag = origin_match.group(1) if origin_match else ""
        cutoff = MAX_CAPTION_LEN - len(origin_tag) - 3
        if cutoff > 0:
            caption_text = caption_text[:cutoff] + "..." + origin_tag
        else:
            caption_text = caption_text[:MAX_CAPTION_LEN]

    if tm.new_file:
        try:
            return await client.send_file(
                recipient, tm.new_file, caption=caption_text, reply_to=tm.reply_to
            )
        except Exception as err:
            logging.error(f"Error enviando new_file: {err}")

    tm.message.text = caption_text
    try:
        return await client.send_message(recipient, tm.message, reply_to=tm.reply_to)
    except Exception as err:
        logging.error(f"Error en send_message: {err}. Intentando envio con respaldo...")
        if has_media:
            try:
                return await client.send_file(
                    recipient, tm.message.media, caption=caption_text[:MAX_CAPTION_LEN], reply_to=tm.reply_to
                )
            except Exception as e2:
                logging.error(f"Fallo fallback send_file: {e2}. Enviando solo texto...")
        return await client.send_message(recipient, caption_text, reply_to=tm.reply_to)


def cleanup(*files: str) -> None:
    """Delete the file names passed as args."""
    for file in files:
        try:
            os.remove(file)
        except FileNotFoundError:
            logging.info(f"File {file} does not exist, so cant delete it.")


def stamp(file: str, user: str) -> str:
    """Stamp the filename with the datetime, and user info."""
    now = str(datetime.now())
    outf = safe_name(f"{user} {now} {file}")
    try:
        os.rename(file, outf)
        return outf
    except Exception as err:
        logging.warning(f"Stamping file name failed for {file} to {outf}. \n {err}")


def safe_name(string: str) -> str:
    """Return safe file name.

    Certain characters in the file name can cause potential problems in rare scenarios.
    """
    return re.sub(pattern=r"[-!@#$%^&*()\s]", repl="_", string=string)


def match(pattern: str, string: str, regex: bool) -> bool:
    if regex:
        return bool(re.findall(pattern, string))
    return pattern in string


def replace(pattern: str, new: str, string: str, regex: bool) -> str:
    def fmt_repl(matched):
        style = new
        s = STYLE_CODES.get(style)
        return f"{s}{matched.group(0)}{s}"

    if regex:
        if new in STYLE_CODES:
            compliled_pattern = re.compile(pattern)
            return compliled_pattern.sub(repl=fmt_repl, string=string)
        return re.sub(pattern, new, string)
    else:
        return string.replace(pattern, new)


def clean_session_files():
    for item in os.listdir():
        if item.endswith(".session") or item.endswith(".session-journal"):
            os.remove(item)
