"""In-memory conversation context & sliding window memory manager."""
from __future__ import annotations

import threading
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional

from .chat_schemas import ChatMessage, ChatSession


class ChatMemoryManager:
    """Quản lý ngữ cảnh và lịch sử hội thoại nhiều lượt (Multi-turn Context).
    
    Quy tắc:
    - Sliding window: Giữ tối đa 20 tin nhắn gần nhất khi đưa vào context LLM.
    - Thread-safe với RLock.
    - Lưu metadata session: title, timestamp, message count.
    """

    def __init__(self, max_context_messages: int = 20):
        self._max_context_messages = max_context_messages
        self._lock = threading.RLock()
        self._sessions: Dict[str, List[ChatMessage]] = {}
        self._session_meta: Dict[str, ChatSession] = {}

    def get_or_create_session(self, session_id: Optional[str] = None) -> str:
        """Đảm bảo session tồn tại và trả về session_id hợp lệ."""
        with self._lock:
            if not session_id:
                session_id = f"session-{uuid.uuid4().hex[:12]}"
            if session_id not in self._sessions:
                now_iso = datetime.now(timezone.utc).isoformat()
                self._sessions[session_id] = []
                self._session_meta[session_id] = ChatSession(
                    sessionId=session_id,
                    title="Cuộc trò chuyện mới",
                    createdAt=now_iso,
                    updatedAt=now_iso,
                    messageCount=0,
                )
            return session_id

    def add_message(
        self,
        session_id: str,
        role: str,
        content: str,
        message_id: Optional[str] = None,
        action: Optional[str] = None,
        rich_cards: Optional[List[Any]] = None,
    ) -> ChatMessage:
        """Thêm 1 tin nhắn vào session."""
        with self._lock:
            sid = self.get_or_create_session(session_id)
            mid = message_id or f"msg-{uuid.uuid4().hex[:12]}"
            now_iso = datetime.now(timezone.utc).isoformat()

            # Chuẩn hóa role
            normalized_role = "model" if role in ("assistant", "model", "bot") else "user"

            msg = ChatMessage(
                id=mid,
                role=normalized_role,
                content=content,
                timestamp=now_iso,
                action=action,
                richCards=rich_cards,
            )
            self._sessions[sid].append(msg)

            # Cập nhật metadata
            meta = self._session_meta[sid]
            meta.messageCount = len(self._sessions[sid])
            meta.updatedAt = now_iso
            meta.lastMessage = content[:80]
            if meta.title == "Cuộc trò chuyện mới" and role == "user":
                # Đặt tiêu đề từ tin nhắn đầu tiên của user
                title_candidate = content.strip().replace("\n", " ")
                meta.title = (title_candidate[:36] + "...") if len(title_candidate) > 36 else title_candidate

            return msg

    def get_context_messages(self, session_id: str) -> List[ChatMessage]:
        """Lấy danh sách tin nhắn trong sliding window (tối đa max_context_messages)."""
        with self._lock:
            msgs = self._sessions.get(session_id, [])
            return msgs[-self._max_context_messages :] if len(msgs) > self._max_context_messages else list(msgs)

    def get_all_messages(self, session_id: str) -> List[ChatMessage]:
        """Lấy toàn bộ tin nhắn trong session."""
        with self._lock:
            return list(self._sessions.get(session_id, []))

    def list_sessions(self, limit: int = 20) -> List[ChatSession]:
        """Lấy danh sách các session sắp xếp theo thời gian cập nhật mới nhất."""
        with self._lock:
            sorted_sessions = sorted(
                self._session_meta.values(),
                key=lambda s: s.updatedAt,
                reverse=True,
            )
            return sorted_sessions[:limit]

    def delete_session(self, session_id: str) -> bool:
        """Xóa một session khỏi bộ nhớ."""
        with self._lock:
            removed = self._sessions.pop(session_id, None) is not None
            self._session_meta.pop(session_id, None)
            return removed

    def clear(self) -> None:
        """Xóa sạch bộ nhớ (chủ yếu dùng cho testing)."""
        with self._lock:
            self._sessions.clear()
            self._session_meta.clear()


# Global in-memory instance
memory_manager = ChatMemoryManager(max_context_messages=20)
