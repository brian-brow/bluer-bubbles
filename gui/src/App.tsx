import { useState, useEffect, useRef } from "react";
import Fuse from "fuse.js";
import "./App.css";

import { readTextFile } from "@tauri-apps/plugin-fs";
import { BaseDirectory } from "@tauri-apps/api/path";

async function loadTheme() {
  try {
    const css = await readTextFile(
      ".config/blue-bubbles/colors.css",
      {
        baseDir: BaseDirectory.Home,
      }
    );

    const style = document.createElement("style");
    style.textContent = css;
    document.head.appendChild(style);
  } catch (e) {
    console.error(e);
  }
}

loadTheme()

interface Message {
  id: number;
  guid: string;
  identifier: string;
  service: string;
  text: string;
  date: number;
  is_from_me: number;
  is_system_message: number;
  group_title: string;
  has_attachments: number;
  first_name: string;
  last_name: string;
  organization: string;
}

const API_BASE = "http://localhost:8001";

function getInitials(firstName: string, lastName: string): string {
  const first = firstName?.trim()?.[0] ?? "";
  const last = lastName?.trim()?.[0] ?? "";
  const initials = (first + last).toUpperCase();
  return initials || "?";
}

function getDisplayName(msg: Message): string {
  const first = msg.first_name?.trim() ?? "";
  const last = msg.last_name?.trim() ?? "";
  const full = (first + " " + last).trim();
  if (full) return full;
  if (msg.organization?.trim()) return msg.organization.trim();
  return msg.identifier;
}

function App() {
  const [allMessages, setAllMessages] = useState<Message[]>([]);
  const [displayedMessages, setDisplayedMessages] = useState<Message[]>([]);

  const [selectedIdentifier, setSelectedIdentifier] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [draftText, setDraftText] = useState("");
  const [searchText, setSearchText] = useState("");

  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, [selectedIdentifier]);

  useEffect(() => {
    fetch(`${API_BASE}/messages/first`)
      .then((res) => res.json())
      .then((data: Message[]) => {
        setAllMessages(data);
        setLoading(false);
      })
      .catch((err) => {
        console.error("Failed to fetch messages:", err);
        setLoading(false);
      });
  }, []);

  // Build the contact list: unique phone -> { firstName, lastName, highestId, lastText }
  // sorted by highestId descending, most recently active first
  const contactMap = new Map<
    string,
    { firstName: string; lastName: string; displayName: string; highestId: number; lastText: string }
  >();
  for (const m of allMessages) {
    const existing = contactMap.get(m.identifier);
    if (!existing || m.id > existing.highestId) {
      contactMap.set(m.identifier, {
        firstName: m.first_name,
        lastName: m.last_name,
        displayName: getDisplayName(m),
        highestId: m.id,
        lastText: m.text,
      });
    }
  }
  const contacts = Array.from(contactMap.entries()).sort(
    (a, b) => b[1].highestId - a[1].highestId
  );

  const contactEntries = contacts.map(([identifier, info]) => ({
    identifier,
    ...info,
  }));

  const fuse = new Fuse(contactEntries, {
    keys: ["displayName"],
    threshold: 0.3,
  });

  const visibleContacts = searchText.trim()
    ? fuse.search(searchText).map((result) => [result.item.identifier, result.item] as const)
    : contacts;

  function fetchContactMessages(identifier: string) {
    fetch(`${API_BASE}/messages/${encodeURIComponent(identifier)}`)
      .then((res) => res.json())
      .then((data: Message[]) => setDisplayedMessages(data))
      .catch((err) => console.error("Failed to fetch contact messages:", err));
  }

  function selectContact(identifier: string) {
    setSelectedIdentifier(identifier);
    fetchContactMessages(identifier);
  }

  function sendMessage(message: string) {
    if (!selectedIdentifier) return;

    fetch(`${API_BASE}/send`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({identifier: selectedIdentifier, message: message})
    })
      .then((res) => res.json())
      .then((data) => console.log("Send result:", data))
      .catch((err) => console.error("Failed to send contact message:", err))
  }

  // Poll the open conversation every 3s while a contact is selected
  useEffect(() => {
    if (!selectedIdentifier) return;
    const interval = setInterval(() => {
      fetchContactMessages(selectedIdentifier);
    }, 3000);
    return () => clearInterval(interval);
  }, [selectedIdentifier]);

  // Poll the full message list every 5s to keep the sidebar (previews/ordering) fresh
  useEffect(() => {
    const interval = setInterval(() => {
      fetch(`${API_BASE}/messages`)
        .then((res) => res.json())
        .then((data: Message[]) => setAllMessages(data))
        .catch((err) => console.error("Failed to refresh sidebar:", err));
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  const selectedContact = selectedIdentifier ? contactMap.get(selectedIdentifier) : null;

  return (
    <main
      className="h-screen w-screen flex flex-row"
      style={{
        fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif",
        backgroundColor: "var(--background)",
      }}
    >
      <div
        className="w-[300px] shrink-0 overflow-y-auto flex flex-col"
        style={{
          borderRight: "1px solid var(--outline-variant)",
          backgroundColor: "var(--surface-container)",
        }}
      >
        <div
          className="px-5 pt-6 pb-3 shrink-0"
          style={{
            fontFamily: "SF Pro Display, system-ui, -apple-system, sans-serif",
            fontSize: "22px",
            fontWeight: 600,
            letterSpacing: "-0.3px",
            color: "var(--text)",
          }}
        >
          Messages
        </div>
        <div
          className="flex items-center"
          style={{
            backgroundColor: "var(--surface-variant)",
            border: "1px solid var(--outline-variant)",
            borderRadius: "20px",
            minHeight: "40px",
            padding: "8px 16px",
            margin: "8px 8px",
          }}
        >
          <input
            ref={inputRef}
            type="text"
            value={searchText}
            onChange={(e) => {
              setSearchText(e.target.value);
            }}
            placeholder="Search"
            className="flex-1 bg-transparent outline-none"
            style={{ fontSize: "15px", fontWeight: 400, color: "var(--text)" }}
          />
          {searchText && (
            <button
              onClick={() => setSearchText("")}
              className="shrink-0 transition-colors"
              style={{ fontSize: "15px", fontWeight: 400, color: "var(--text-muted)" }}
              onMouseEnter={(e) => (e.currentTarget.style.color = "var(--text)")}
              onMouseLeave={(e) => (e.currentTarget.style.color = "var(--text-muted)")}
            >
              ×
            </button>
          )}
        </div>
        <ul className="flex-1 overflow-y-auto">
          {loading && (
            <li className="px-5 py-3" style={{ fontSize: "13px", color: "var(--text-muted)" }}>
              Loading…
            </li>
          )}
          {visibleContacts.map(([identifier, { firstName, lastName, displayName, lastText }]) => {
            const isSelected = selectedIdentifier === identifier;
            return (
              <li
                key={identifier}
                onClick={() => selectContact(identifier)}
                className="flex items-center gap-3 px-4 py-2.5 cursor-pointer transition-transform active:scale-[0.98]"
                style={{
                  backgroundColor: isSelected ? "var(--surface-bright)" : "transparent",
                }}
                onMouseEnter={(e) => {
                  if (!isSelected) e.currentTarget.style.backgroundColor = "var(--surface-variant)";
                }}
                onMouseLeave={(e) => {
                  if (!isSelected) e.currentTarget.style.backgroundColor = "transparent";
                }}
              >
                <div
                  className="shrink-0 w-11 h-11 rounded-full flex items-center justify-center"
                  style={{
                    backgroundColor: "var(--secondary)",
                    color: "var(--on-secondary)",
                    fontSize: "15px",
                    fontWeight: 600,
                  }}
                >
                  {getInitials(firstName, lastName)}
                </div>
                <div className="min-w-0 flex-1">
                  <div
                    className="truncate"
                    style={{ fontSize: "14px", fontWeight: 600, letterSpacing: "-0.2px", color: "var(--text)" }}
                  >
                    {displayName}
                  </div>
                  <div
                    className="truncate"
                    style={{ fontSize: "13px", fontWeight: 400, color: "var(--text-muted)" }}
                  >
                    {lastText}
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      </div>

      <div className="flex-1 flex flex-col" style={{ backgroundColor: "var(--background)" }}>
        {selectedContact ? (
          <>
            <div
              className="h-16 shrink-0 flex items-center justify-center"
              style={{ borderBottom: "1px solid var(--outline-variant)" }}
            >
              <div style={{ fontSize: "15px", fontWeight: 600, letterSpacing: "-0.2px", color: "var(--text)" }}>
                {selectedContact.displayName}
              </div>
            </div>

            <div className="flex-1 overflow-y-auto px-6 py-6 flex flex-col justify-end gap-2">
              {[...displayedMessages]
                .sort((a, b) => a.id - b.id)
                .map((msg) => {
                  const fromMe = !!msg.is_from_me;
                  return (
                    <div
                      key={msg.id}
                      className={`flex ${fromMe ? "justify-end" : "justify-start"}`}
                    >
                      <div
                        className="max-w-[60%] px-4 py-2"
                        style={{
                          backgroundColor: fromMe ? "var(--primary)" : "var(--surface-bright)",
                          color: fromMe ? "var(--on-primary)" : "var(--text)",
                          borderRadius: "18px",
                          fontSize: "15px",
                          fontWeight: 400,
                          lineHeight: 1.35,
                        }}
                      >
                        {msg.text}
                      </div>
                    </div>
                  );
                })}
            </div>

            <div
              className="shrink-0 px-4 py-3 flex items-end gap-2"
              style={{ borderTop: "1px solid var(--outline-variant)" }}
            >
              <div
                className="flex-1 flex items-center"
                style={{
                  backgroundColor: "var(--surface-variant)",
                  border: "1px solid var(--outline-variant)",
                  borderRadius: "20px",
                  minHeight: "40px",
                  padding: "8px 16px",
                }}
              >
                <input
                  ref={inputRef}
                  type="text"
                  value={draftText}
                  onChange={(e) => setDraftText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && draftText.trim()) {
                      sendMessage(draftText);
                      setDraftText("");
                    }
                  }}
                  placeholder="iMessage"
                  className="flex-1 bg-transparent outline-none"
                  style={{ fontSize: "15px", fontWeight: 400, color: "var(--text)" }}
                />
              </div>
              <button
                disabled={!draftText.trim()}
                onClick={() => {
                  sendMessage(draftText);
                  setDraftText("");
                }}
                className="shrink-0 w-8 h-8 rounded-full flex items-center justify-center transition-transform active:scale-[0.95] disabled:opacity-40"
                style={{ backgroundColor: "var(--primary)" }}
              >
                <svg
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="var(--on-primary)"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M12 19V5M5 12l7-7 7 7" />
                </svg>
              </button>
            </div>
          </>
        ) : (
            <div className="flex-1 flex items-center justify-center">
              <div style={{ fontSize: "17px", fontWeight: 400, color: "var(--text-muted)" }}>
                Select a conversation
              </div>
            </div>
          )}
      </div>
    </main>
  );
}

export default App;
