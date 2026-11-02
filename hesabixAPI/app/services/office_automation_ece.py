"""ECE 1.01 XML builder/parser (Electronic Correspondence Exchange).

Schema follows the national protocol v1.01 used by Iranian OA products:
root <letter> with Protocol/Software/Sender/Receiver/LetterNo/LetterDateTime/
Subject/Priority/Classification/Origins/Attachments/RelatedLetters.
"""
from __future__ import annotations

import base64
import html
from datetime import date, datetime
from typing import Any, Dict, List, Optional
from xml.etree import ElementTree as ET

_ECE_NS_PROTOCOL = "ECE"
_ECE_VERSION = "1.01"
_SOFTWARE_NAME = "Hesabix"
_SOFTWARE_VERSION = "2.0"
_SOFTWARE_DEVELOPER = "Hesabix"
_SOFTWARE_GUID = "8f3c1a2e-6b14-4d9a-9c71-hesabix-oa-ece"

_PRIORITY = {
	"normal": ("1", "عادی"),
	"urgent": ("2", "فوری"),
	"immediate": ("3", "آنی"),
}
_CLASSIFICATION = {
	"normal": ("1", "عادی"),
	"confidential": ("2", "محرمانه"),
	"highly_confidential": ("3", "خیلی محرمانه"),
	"secret": ("4", "سری"),
}
_CLASSIFICATION_BY_CODE = {code: key for key, (code, _name) in _CLASSIFICATION.items()}
_PRIORITY_BY_CODE = {code: key for key, (code, _name) in _PRIORITY.items()}


def _attr(el: Optional[ET.Element], name: str, default: str = "") -> str:
	if el is None:
		return default
	return (el.get(name) or default).strip()


def _text(el: Optional[ET.Element], default: str = "") -> str:
	if el is None or el.text is None:
		return default
	return str(el.text).strip()


def _party_el(tag: str, payload: Dict[str, Any], *, receive_type: Optional[str] = None) -> ET.Element:
	el = ET.Element(tag)
	el.set("Name", str(payload.get("name") or ""))
	el.set("Organization", str(payload.get("organization") or ""))
	el.set("Position", str(payload.get("position") or ""))
	el.set("Code", str(payload.get("code") or ""))
	el.set("Department", str(payload.get("department") or ""))
	el.set("Any", "")
	if receive_type is not None:
		el.set("ReceiveType", receive_type)
	return el


def _binary_el(tag: str, *, content: bytes, description: str, filename: str, mime: str) -> ET.Element:
	ext = ""
	if "." in filename:
		ext = filename[filename.rfind(".") :]
	el = ET.Element(tag)
	el.text = base64.b64encode(content).decode("ascii")
	el.set("Description", description or filename)
	el.set("Extension", ext)
	el.set("ContentType", mime or "application/octet-stream")
	el.set("Any", "")
	return el


def build_ece_xml(
	*,
	sender: Dict[str, Any],
	receiver: Dict[str, Any],
	letter_no: str,
	letter_date: date,
	subject: str,
	urgency: str = "normal",
	confidentiality: str = "normal",
	keywords: str = "",
	body: Optional[str] = None,
	origins: Optional[List[Dict[str, Any]]] = None,
	attachments: Optional[List[Dict[str, Any]]] = None,
	other_receivers: Optional[List[Dict[str, Any]]] = None,
	related_letters: Optional[List[Dict[str, Any]]] = None,
	calendar_label: str = "jalali",
	letter_datetime: Optional[datetime] = None,
) -> str:
	prio_code, prio_name = _PRIORITY.get(urgency, _PRIORITY["normal"])
	cls_code, cls_name = _CLASSIFICATION.get(confidentiality, _CLASSIFICATION["normal"])
	show_as = "jalali" if calendar_label == "jalali" else "gregorian"
	dt = letter_datetime or datetime.combine(letter_date, datetime.min.time())
	dt_text = dt.strftime("%Y-%m-%dT%H:%M:%S")

	root = ET.Element("letter", Any="")
	protocol = ET.SubElement(root, "Protocol", Name=_ECE_NS_PROTOCOL, Version=_ECE_VERSION, Any="")
	ET.SubElement(
		root,
		"Software",
		Version=_SOFTWARE_VERSION,
		SoftwareDeveloper=_SOFTWARE_DEVELOPER,
		GUID=_SOFTWARE_GUID,
		Any="",
	).text = _SOFTWARE_NAME
	root.append(_party_el("Sender", sender))
	root.append(_party_el("Receiver", receiver, receive_type="original"))
	others = ET.SubElement(root, "OtherReceivers")
	for item in other_receivers or []:
		others.append(_party_el("OtherReceiver", item, receive_type=str(item.get("receive_type") or "cc")))
	ET.SubElement(root, "LetterNo", Any="").text = letter_no
	ET.SubElement(root, "LetterDateTime", ShowAs=show_as, Any="").text = dt_text
	related_el = ET.SubElement(root, "RelatedLetters")
	for rel in related_letters or []:
		node = ET.SubElement(related_el, "RelatedLetter")
		ET.SubElement(
			node,
			"RelatedLetterDateTime",
			ShowAs=str(rel.get("show_as") or show_as),
			Any="",
		).text = str(rel.get("date") or "")
		ET.SubElement(node, "RelatedLetterNO", Any="").text = str(rel.get("number") or "")
		node.append(_party_el("RelatedLetterSender", rel.get("sender") or {}))
		ET.SubElement(
			node,
			"RelationType",
			Any="",
			code=str(rel.get("kind") or "related"),
			Name=str(rel.get("kind_title") or rel.get("kind") or "related"),
		)
	ET.SubElement(root, "Subject", Any="").text = subject
	ET.SubElement(root, "Priority", Code=prio_code, Name=prio_name, Any="")
	ET.SubElement(root, "Classification", Code=cls_code, Name=cls_name, Any="")
	ET.SubElement(root, "Keywords", Keyword=keywords or "", Any="")
	origins_el = ET.SubElement(root, "Origins")
	if body:
		origins_el.append(
			_binary_el(
				"Origin",
				content=body.encode("utf-8"),
				description="letter-body",
				filename="body.txt",
				mime="text/plain; charset=utf-8",
			)
		)
	for item in origins or []:
		origins_el.append(
			_binary_el(
				"Origin",
				content=item["content"],
				description=str(item.get("description") or "origin"),
				filename=str(item.get("filename") or "origin.bin"),
				mime=str(item.get("mime") or "application/octet-stream"),
			)
		)
	atts_el = ET.SubElement(root, "Attachments")
	for item in attachments or []:
		atts_el.append(
			_binary_el(
				"Attachment",
				content=item["content"],
				description=str(item.get("description") or item.get("filename") or "attachment"),
				filename=str(item.get("filename") or "file.bin"),
				mime=str(item.get("mime") or "application/octet-stream"),
			)
		)
	# protocol kept referenced so linters don't drop the element
	_ = protocol
	xml_bytes = ET.tostring(root, encoding="utf-8")
	return '<?xml version="1.0" encoding="UTF-8"?>\n' + xml_bytes.decode("utf-8")


def parse_ece_xml(xml_text: str) -> Dict[str, Any]:
	text = (xml_text or "").lstrip("\ufeff").strip()
	if not text:
		raise ValueError("ECE XML is empty.")
	root = ET.fromstring(text)
	if root.tag.split("}")[-1].lower() != "letter":
		raise ValueError("ECE root element must be <letter>.")

	def child(tag: str) -> Optional[ET.Element]:
		for el in root:
			if el.tag.split("}")[-1] == tag:
				return el
		return None

	sender = child("Sender")
	receiver = child("Receiver")
	prio = child("Priority")
	cls = child("Classification")
	letter_dt = child("LetterDateTime")
	origins: List[Dict[str, Any]] = []
	attachments: List[Dict[str, Any]] = []
	for parent_tag, bucket in (("Origins", origins), ("Attachments", attachments)):
		parent = child(parent_tag)
		if parent is None:
			continue
		item_tag = "Origin" if parent_tag == "Origins" else "Attachment"
		for el in parent:
			if el.tag.split("}")[-1] != item_tag:
				continue
			raw = (el.text or "").strip()
			content = b""
			if raw:
				try:
					content = base64.b64decode(raw)
				except Exception:
					content = raw.encode("utf-8")
			bucket.append(
				{
					"description": _attr(el, "Description"),
					"extension": _attr(el, "Extension"),
					"mime": _attr(el, "ContentType"),
					"content": content,
				}
			)

	other: List[Dict[str, Any]] = []
	others_el = child("OtherReceivers")
	if others_el is not None:
		for el in others_el:
			if el.tag.split("}")[-1] != "OtherReceiver":
				continue
			other.append(
				{
					"name": _attr(el, "Name"),
					"organization": _attr(el, "Organization"),
					"position": _attr(el, "Position"),
					"code": _attr(el, "Code"),
					"department": _attr(el, "Department"),
					"receive_type": _attr(el, "ReceiveType"),
				}
			)

	body = ""
	for origin in origins:
		if origin.get("description") == "letter-body" or str(origin.get("mime") or "").startswith("text/plain"):
			try:
				body = origin["content"].decode("utf-8")
				break
			except Exception:
				continue

	return {
		"protocol": _attr(child("Protocol"), "Name") or _ECE_NS_PROTOCOL,
		"version": _attr(child("Protocol"), "Version") or _ECE_VERSION,
		"sender": {
			"name": _attr(sender, "Name"),
			"organization": _attr(sender, "Organization"),
			"position": _attr(sender, "Position"),
			"code": _attr(sender, "Code"),
			"department": _attr(sender, "Department"),
		},
		"receiver": {
			"name": _attr(receiver, "Name"),
			"organization": _attr(receiver, "Organization"),
			"position": _attr(receiver, "Position"),
			"code": _attr(receiver, "Code"),
			"department": _attr(receiver, "Department"),
			"receive_type": _attr(receiver, "ReceiveType"),
		},
		"other_receivers": other,
		"letter_no": _text(child("LetterNo")),
		"letter_datetime": _text(letter_dt),
		"show_as": _attr(letter_dt, "ShowAs") or "jalali",
		"subject": _text(child("Subject")),
		"urgency": _PRIORITY_BY_CODE.get(_attr(prio, "Code"), "normal"),
		"confidentiality": _CLASSIFICATION_BY_CODE.get(_attr(cls, "Code"), "normal"),
		"keywords": _attr(child("Keywords"), "Keyword"),
		"body": body,
		"origins": origins,
		"attachments": attachments,
	}


def escape_plain(value: str) -> str:
	return html.escape(value or "")
