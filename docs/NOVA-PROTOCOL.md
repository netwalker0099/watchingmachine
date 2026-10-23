# Nova addons: addon-message protocols

How **Nova World Buffs 3.42** (NWB) and **Nova Instance Tracker 2.31**
(NIT), by Novaspark, talk to each other's users. It was worked out from their
released code so that Watching Machine can work alongside them. Their code
is read, not copied: neither states a licence, so treat both as all rights
reserved. Our encoder and decoder are written separately, and any library we
bundle (LibSerialize: MIT, LibDeflate: LGPL-3) comes from its own source
under its own licence.

File:line references are to the released addons, in `nova-src/`, which is
not committed. Uncertain points are marked.

## Our decisions

- **NIT (instance resets): listen only** (built in 3.23,
  `Modules/NovaCompat.lua`).
  - We show NIT users' reset notices, checking they come from the group
    leader (NIT itself doesn't check), and mark the instance as reset.
  - We don't send in their format; our own reset announcement is a normal
    party / raid chat line.
- **NWB: listen only, and only after review.**
  - On TBC, NWB syncs little: Terokkar tower timers, the dailies, and layer
    data.
  - Its timer data carries an anti-forgery token that the author
    deliberately hides in obfuscated code.
  - Recreating that to inject data into NWB users' clients goes against what
    the author clearly intended. It also risks writing bad keys into their
    saved variables and spreading through their guilds (see the risks
    below). So **Watching Machine does not broadcast to NWB**, and this
    document doesn't record how to make the token.
- **NWB's reset notices never reach NIT users** (they're sent with version
  0, which NIT drops). That's one more reason to send NIT's own format.

---

# Part 1 — Nova Instance Tracker


Source: `/home/user/watchingmachine/nova-src/NovaInstanceTracker/` (TOC `Version: 2.31`, Interface `11509, 16001, 20506, 40402, 50504, 120105`). Paths below are relative to that folder unless prefixed `NWB/` (= `/home/user/watchingmachine/nova-src/NovaWorldBuffs/`, v3.42).
Notation: **[UNCERTAIN]** marks things I inferred and did not verify directly in the code.

## 0. TL;DR

- One prefix, `"NIT"`, sent through AceComm-3.0. The payload is a single Lua **string** `"<cmd> <version> <data>"`. It is encoded as: LibSerialize, then raw DEFLATE (LibDeflate `CompressDeflate`, level 9), then LibDeflate `EncodeForWoWAddonChannel`, then AceComm framing.
- The protocol has very few messages: `version`, `instanceReset`, `instanceResetNoMsg`, `instanceResetOther` and `douse`. It does **not** sync lockouts, the instance log or the trade log.
- A reset notice is sent only by the **group leader**, when their client shows the system message "X has been reset." or "Cannot reset X. There are players still inside the instance.". It goes to RAID, INSTANCE_CHAT or PARTY.
- A receiving NIT prints `"<instance> has been reset by the group leader (<name>)."` only for `instanceResetNoMsg` and `instanceResetOther`. It does **not** check whether the sender is really the leader.
- **NWB's reset notice is dead in NIT 2.31.** NWB sends version `0`, and NIT drops every message whose version is below `1.00` *before* it looks at the command.

## 1. Prefix, transport, priority

- Prefix: `NIT.commPrefix = "NIT"` (NovaInstanceTracker.lua:59). It is registered via `self:RegisterComm(self.commPrefix)` (NovaInstanceTracker.lua:132). AceComm calls `C_ChatInfo.RegisterAddonMessagePrefix` (Lib/AceComm-3.0/AceComm-3.0.lua, `RegisterComm`).
- The addon is an AceAddon with the AceComm-3.0 mixin (NovaInstanceTracker.lua:6). The handler is the default `NIT:OnCommReceived` (Modules/Data.lua:56).
- Sending: `NIT:SendCommMessage(NIT.commPrefix, data, distribution, target)` (Modules/Data.lua:170). No priority is passed, so AceComm uses `"NORMAL"`. Throttling is done by ChatThrottleLib (the CTL queue name is the prefix).
- AceComm-3.0 MINOR 14 framing (Lib/AceComm-3.0/AceComm-3.0.lua):
  - Max single message: 255 bytes.
  - If the text starts with a byte in `\001`-`\009`, AceComm prepends `\004` (escape) on send and strips it on receive.
  - Messages over 255 bytes are split into 254-byte chunks marked `\001` (first), `\002` (next) and `\003` (last). NIT messages are tiny, so multipart is effectively never used.
  - The receiver runs `Ambiguate(sender, "none")`, so a same-realm sender arrives as a bare `Name`.
- There is also a raw `CHAT_MSG_ADDON` listener (Modules/Data.lua:222, 328-340). It only marks `NIT.hasAddon[normalizedSender] = "0"` when the sender is first seen. It does not decode anything.

## 2. Channels

`NIT:sendGroupComm(msg)` (NovaInstanceTracker.lua:6401-6409) picks the channel in this order:
1. `RAID` if `IsInRaid()`
2. `INSTANCE_CHAT` if `IsInGroup(LE_PARTY_CATEGORY_INSTANCE)`
3. `PARTY` if `IsInGroup()`

`NIT:sendComm(distribution, string, target)` (Modules/Data.lua:139-171) applies these rules:
- It does not send to yourself as WHISPER, and does not send to GUILD when you are not in a guild.
- In a battleground or arena, only `GUILD` is allowed (line 150).
- `CHANNEL` targets are converted to the channel number. `target` is kept only for WHISPER.
- SAY and YELL would use the chat-channel codec (lines 165-166), but NIT never sends on them, and the receiver drops them (lines 87-89).

When each channel is used:

| When | Channel | Message |
|---|---|---|
| Logon (isLogon), after 10 s | GUILD | `version` (Data.lua:298-301) |
| `GROUP_JOINED` / `GROUP_FORMED` while in a group (throttled 3 s) | group | `version` (Data.lua:439-448) |
| Leader sees a reset system message | group | `instanceReset` / `instanceResetNoMsg` (NovaInstanceTracker.lua:303-311) |
| Player casts Aqual Quintessence douse (spell 21358) in Molten Core (map 409) near a boss | group | `douse` (Modules/Douses.lua:246) |

The receiver accepts every distribution except SAY and YELL, including WHISPER and GUILD.

## 3. Encode/decode pipeline (exact)

### Encode (Data.lua:162-170)

1. Build the plaintext string `cmd .. " " .. version .. " " .. data`, single-space separated. `version` is the TOC Version string, `"2.31"`. In Douses.lua it is the number `NIT.version`, which concatenates to the same text.
2. Serialize with `LibSerialize:Serialize(str)`. NIT uses **LibSerialize, not AceSerializer** (NovaInstanceTracker.lua:62), even though AceSerializer is embedded. The library is LibSerialize MINOR 1 (Lib/LibSerialize-1.0.0/LibSerialize.lua:254). Output bytes:
   - byte `0x01`: the format version, `_WriteByte(MINOR)` (line 1112). The decoder asserts this value (line 1151).
   - then one string object (lines 922-939):
     - length < 16: one type byte `len*16 + 2` (`CCCC 0010`), then the raw bytes.
     - length 16-255: type byte `0x70` (STR_8 = 14, ×8), then 1 length byte, then the bytes.
     - length 256-65535: `0x78` (STR_16), then a 2-byte big-endian length (`IntToString`, line 451).
     - length up to 2^24: `0x80` (STR_24), then a 3-byte length.
   - Example: `"instanceResetNoMsg 2.31 Hellfire Ramparts"` (41 chars) serializes to `01 70 29` followed by the 41 ASCII bytes.
3. Compress with `LibDeflate:CompressDeflate(serialized, {level = 9})`. The output is a **raw DEFLATE stream (RFC 1951)** with no zlib or gzip header or checksum. Any valid raw DEFLATE stream decodes on the NIT side, including stored or fixed-Huffman blocks. The bytes do not need to match LibDeflate's output.
4. Encode with `LibDeflate:EncodeForWoWAddonChannel(compressed)`. This calls `CreateCodec("\000", "\001", "")` (Lib/LibDeflate/LibDeflate.lua:3067-3069). Working through `CreateCodec` (around line 2907) gives:
   - `0x00` becomes `0x01 0x02`
   - `0x01` becomes `0x01 0x03`
   - every other byte passes through unchanged.
   - Decode is the reverse. An `0x01` followed by anything else, or a trailing `0x01`, makes decode fail (it returns nil).
5. `SendCommMessage("NIT", encoded, dist, target)`. AceComm adds a leading `\004` if the first encoded byte is in `0x01`-`0x09`, and splits if over 255 bytes.

### Decode (Data.lua:56-136)

1. AceComm un-framing gives `(prefix, text, distribution, sender)`.
2. Self-echo check: if the sender is the player (with or without realm), set `hasAddon[me] = version` and return (lines 71-74).
3. **Cross-realm senders are dropped.** After `Ambiguate`, any sender name containing `-` (that is, one carrying a realm) is ignored (lines 75-80). The condition `realm ~= nil or ...` is true for any realm suffix. A sender without a realm gets `-<NormalizedRealm>` appended.
4. Drop SAY and YELL. Otherwise `DecodeForWoWAddonChannel`, then `DecompressDeflate`, then `LibSerialize:Deserialize`. On failure it debug-logs and returns (lines 86-102).
5. `NIT:explode(" ", deserialized, 2)` (NovaInstanceTracker.lua:755-773) is a plain-text split with a limit. It returns `{cmd, version, rest}`, where `rest` is everything after the second space, spaces included. `rest` is nil when the string contains only one space.
   - The deserialized value **must be a string**. A table or number causes a Lua error in `string.find` (an error inside the handler, not a clean reject).
6. `hasAddon[sender] = remoteVersion`. If `tonumber(remoteVersion)` is nil, return. **If it is below `1.00`, return** (lines 113-122).
7. Dispatch on `cmd` (lines 123-134), then `versionCheck(remoteVersion)` (line 135).

## 4. Message types

All examples are plaintext before serialization. `<inst>` is the instance name captured from the sender's localized system message, so it is in the **sender's client language**.

| cmd | Format | Sender | Receiver action |
|---|---|---|---|
| `version` | `version 2.31 check` | Data.lua:189-196. The trailing `check` is a legacy token (comment at line 190). | No dedicated handler. It only goes through `hasAddon` and `versionCheck`. |
| `instanceReset` | `instanceReset 2.31 Hellfire Ramparts` | Leader whose "Group Instance Reset" option (`instanceResetMsg`, default true, Options.lua:833) is **on**. That leader also posts a party or raid chat line (see below). | `instanceResetComm` does **nothing** (Data.lua:199-202). It relies on the chat line. |
| `instanceResetNoMsg` | `instanceResetNoMsg 2.31 The Blood Furnace` | Leader with that option **off**. | Prints `"<inst> has been reset by the group leader (<who>)."` to the local chat frame with the `[NIT]` prefix (Data.lua:205-209). `<who>` is the sender name without realm. |
| `instanceResetOther` | `instanceResetOther 0 <inst>` | NWB, when NIT is not loaded (section 6). | Same print as NoMsg (Data.lua:212-216). It is **unreachable** for version 0 because of the `< 1.00` gate. |
| `douse` | `douse 2.31 12056 MAGE` (`npcID` and `UnitClass` English token) | Douses.lua:228-268 | Recorded only if the receiver is in MC (`currentInstanceID == 409`), into `instances[1].douses[npcID] = {name, class, time}` (Douses.lua:270-286). |

Requests, lockout or log sync, and trade-log sync: **none exist**. The comment at Data.lua:55 says the comm code was copied from NWB "incase of future stuff". `grep` finds no other `sendComm` or `sendGroupComm` callers.

### Reset trigger (sender side, NovaInstanceTracker.lua:265-316)

There is a `CHAT_MSG_SYSTEM` listener. There is **no** `ResetInstances` hook. The only `ResetInstances()` call is the debug auto-reset `NITAUTORESET` (Data.lua:1806-1819).

The patterns are built from Blizzard globals with `%s` replaced by `(.+)`, so they are locale-correct:

| Global | Example text | `instance` | `success` | Chat text |
|---|---|---|---|---|
| `INSTANCE_RESET_SUCCESS` | "%s has been reset." | captured | true | the original msg |
| `INSTANCE_RESET_FAILED` | "Cannot reset %s.  There are players still inside the instance." | captured | **true** (players outside are reset) | `inst .. " " .. L["playersStillInside"]` = "X has been reset (Players still inside old instance can zone out and enter new)." |
| `INSTANCE_RESET_FAILED_ZONING` / `_OFFLINE` | | captured | false | the original msg |

Then:
- If `success` and `UnitIsGroupLeader("player")`, send the comm: `instanceReset` or `instanceResetNoMsg` plus version plus `instance` (line 310).
- If `instanceResetMsg` is on and an instance was matched, it also sends a plain chat line `"[NIT] " .. stripColors(text)` to RAID, INSTANCE_CHAT or PARTY via `NIT:sendGroup` (lines 313-315, 6391-6399). The chat line has **no leader check**, and it is also sent for the zoning and offline failures.
- Korean `|1이;가;` is stripped from the chat text only (line 302).

## 5. Receiver behaviour summary

- The only visible effect is a local chat print, and only for `instanceResetNoMsg` and (in theory) `instanceResetOther`.
- Received resets do **not** alter NIT's instance log or lockout counts.
- There is no check that the sender is the group leader, is in your group, or sent on a group distribution. A WHISPER or GUILD `instanceResetNoMsg` would print too.
- There is no dedupe or throttle on the receiver side.
- For `instanceReset`, NIT users see the leader's normal chat line `[NIT] Hellfire Ramparts has been reset.` instead.
  - A third addon can also parse `CHAT_MSG_PARTY`, `CHAT_MSG_RAID` and `CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER` lines beginning `[NIT] `.
  - Each such line has a matching `instanceReset` comm only when the line comes from the leader and is a success or players-inside case.

## 6. NWB carrying reset notices (NWB/NovaWorldBuffs.lua:5089-5124)

- NWB registers the `"NIT"` prefix **raw**, without AceComm (line 5094). It sends with a raw `C_ChatInfo.SendAddonMessage("NIT", data, "RAID"|"PARTY")`. It never uses INSTANCE_CHAT and **never adds the AceComm `\004` escape**.
- It does nothing if NovaInstanceTracker is loaded (line 5101).
- It sends only if it is the group leader.
- Plaintext is `"instanceResetOther 0 " .. instance`, run through the same LibSerialize, LibDeflate level 9 and addon-channel encoding (lines 5112-5116).
- **Bug:** on a *success* message, NWB extracts the name using the `INSTANCE_RESET_FAILED` pattern (line 5107), which gives nil. So NWB only ever sends on the "players still inside" case. **[UNCERTAIN only in that I didn't run it; the logic is unambiguous for enUS.]**
- **Effect on NIT 2.31:** version `"0"` hits the `< 1.00` return (Data.lua:120), so nothing is printed. A third addon can still decode these messages. Treat them as "group leader reset `<inst>` (some players were still inside)".
- Raw-send caveat: if an NWB payload's first byte is `0x01`-`0x09`, AceComm receivers treat it as a control byte and may lose it. **[UNCERTAIN how often this happens]**. A fixed-Huffman final block starts with low bits `011`, which is likely the common case for tiny inputs. Its first byte is ≥ `0x0B` unless the following bits are zero. A stored block would start with `0x01`.

## 7. Version gating, trust, throttling

- `remoteVersion` must satisfy `tonumber` and be **≥ 1.00**, or the message is ignored (Data.lua:114-122).
- `versionCheck` (Data.lua:173-187): if remote is greater than the local version, NIT prints "out of date" at most once per 4 h (`lastVersionMsg`, 14400 s) and stores `latestRemoteVersion`. **A third addon should send a version between `1.00` and the current NIT version (for example `1.00`)** so that NIT users are not nagged. Version `0` is explicitly treated as "from NWB" there.
- Trust:
  - Same-realm only (cross-realm is dropped).
  - Senders are not authenticated.
  - Leader status is not re-checked on receive.
  - There is no payload length or format validation beyond the decode steps.
- Throttling:
  - Outgoing traffic goes through ChatThrottleLib at NORMAL priority.
  - Version messages on group join use `throddleEventByFunc(event, 3, "sendVersion")`, about 3 s.
  - Resets fire once per system message, with no extra throttle.

## 8. NIT's own instance tracking (design reference)

- **Entry/exit.** On `PLAYER_ENTERING_WORLD` (Data.lua:1007-1034):
  - If `IsInInstance()`, call `enteredInstance()` after 0.5 s, with reload and logon variants.
  - Otherwise, if `NIT.inInstance`, call `leftInstance()`.
  - Exit is also recorded on logout (`ADDONS_UNLOADING`, Data.lua:1043-1047) and `PLAYER_CAMPING`.
  - Zoning directly from one instance into another with a different name closes the old record (Data.lua:1555-1559).
  - Ghost runs (`PLAYER_UNGHOST` / `isGhost`) do not create a new record (Data.lua:1576, 341-347).
  - A reload inside an instance keeps the existing record (line 1584).
- **New record** (Data.lua:1584-1662): `{instanceName, instanceID = GetInstanceInfo() 8th return (the map ID, e.g. 540), difficultyID, type, enteredTime = GetServerTime(), leftTime = 0, ...}`, inserted at index 1 (newest first).
  - `leftTime` is set in `recordLeftInstanceStats` (Data.lua:1765).
- **Per-run instance identity.** This is the server instance ID, taken from the **zoneUID field of creature or cast GUIDs**: `Creature-0-<server>-<map>-<zoneUID>-<npcID>-<spawn>`, field 5 (Data.lua:2135).
  - Sources: the first creature in combat log damage events (Data.lua:1290-1300), the first `UNIT_SPELLCAST_*` cast GUID (1305-1312), and target, mouseover and nameplate (349-357).
  - Companion pets are excluded.
  - It is stored as `instances[1].zoneID` (Data.lua:2168-2172).
- **Duplicate avoidance** (Data.lua:2150-2165, 2188-2229):
  - If the previous record `instances[2].zoneID` equals the new zoneUID and the current record has no zoneID yet (option `detectSameInstance`, default true), NIT merges: it adds mob, xp and money counts into `[2]`, removes `[1]`, and prints "same instance".
  - Resets do not factor in; identity is purely the zoneUID.
- **Lockout counting** (`getInstanceLockoutInfo`, Data.lua:2391-2428):
  - Count records for which `instanceHasLockout` is true. Excluded are PvP, delves, scenarios and `zones[id].noLockout` entries before Cataclysm (Data.lua:4489-4500).
  - A record counts toward the hourly total if `leftTime` is within 3600 s, **falling back to `enteredTime`** if it has not been left yet. The 24 h count works the same way with 86400 s.
  - Because the list is newest first, `hourTimestamp` ends as the **oldest** qualifying time. "Next free" is therefore `3600 - (now - oldest)`.
  - Limits (NovaInstanceTracker.lua:78-103): `hourlyLimit = 5` for Classic, TBC, Wrath and Cata; 10 for Era "Forever" (TOC 16xxx), MoP+ and retail. **`dailyLimit = 999` everywhere, so in 2.31 NIT does not enforce 30 per 24 h on TBC.** It only displays the 24 h count.
  - **Hourly vs daily:** the daily lockout is reported when `count24 >= dailyLimit` and its time-left is the larger of the two. Otherwise the hourly lockout is reported when `count1h >= hourlyLimit` (NovaInstanceTracker.lua:1403-1418).
  - The ticker prints "you can enter a new instance now" when a count drops from the limit (NovaInstanceTracker.lua:932-946).
  - `TRANSFER_ABORT_TOO_MANY_INSTANCES` in `CHAT_MSG_SYSTEM` prints the lockout info (NovaInstanceTracker.lua:294-300).

## 9. Minimum viable interop

**Receive.** Use AceComm-3.0 if you can (`RegisterComm("NIT")`); otherwise do the following by hand:

1. On `CHAT_MSG_ADDON` with prefix `"NIT"`:
   - If the first byte is `\004`, strip it.
   - If it is `\001`/`\002`/`\003`, reassemble per sender, distribution and prefix.
2. Decode the addon-channel codec: `\001\002` becomes `\000`, `\001\003` becomes `\001`, any other `\001` sequence means reject.
3. Raw inflate the result.
4. Check that byte 1 is `0x01`. Parse one string object: `b & 0x0F == 0x02` means length `b >> 4`; `0x70` means a 1-byte length; `0x78` means a 2-byte big-endian length. Reject anything else.
5. Split at the first two spaces into `cmd`, `ver` and `data`. Require `tonumber(ver)`.
6. Act on these commands:
   - `instanceReset`, `instanceResetNoMsg`, `instanceResetOther` (accept `ver` 0 for NWB): `data` is a localized instance name. Validate that the sender is `UnitIsGroupLeader(sender)` and is in your group. NIT does not check this; you should.
   - `version`: note that the sender has NIT.
   - Ignore `douse`.

Optionally also parse group chat lines starting `[NIT] `.

**Send** (so that NIT prints your notice):

1. Send `instanceResetNoMsg 1.00 <localized instance name>`.
2. Run it through the pipeline in section 3.
3. Send on `RAID`, `INSTANCE_CHAT` or `PARTY` using AceComm, or raw with the `\004` escape rule applied yourself.
4. Send only as the leader, and only after seeing `INSTANCE_RESET_SUCCESS` or `INSTANCE_RESET_FAILED`.

Do not use `instanceReset`: NIT ignores it and expects a chat line. Do not use version `0`, because it is dropped. Do not send a version above NIT's, because it triggers an out-of-date nag.

**Risks.**
- Cross-realm group members (connected realms, if any on Anniversary) never receive your message, because NIT drops senders with a realm suffix. **[UNCERTAIN whether Anniversary returns realm-suffixed names for connected-realm players]**
- Instance names are in the sender's locale.
- Future NIT versions may change the version gate or the commands.
- Using the `NIT` prefix means NIT users mark you as a NIT user in `hasAddon`. This is harmless.
- Sending a non-string serialized value throws a Lua error in NIT users' clients. Never do it.
- NWB's raw sends may arrive with an unescaped leading control byte.
- Raw DEFLATE must have no zlib header (strip the 2-byte header and 4-byte Adler checksum if your compressor adds them). In-game, simply embed LibDeflate.

## 10. Licence

- **NovaInstanceTracker itself ships no licence file or header.** Its readme.txt and Modules/README.txt contain only a description and the CurseForge URL. Treat it as all rights reserved. This spec describes behaviour only.
- Embedded libraries:
  - LibSerialize: MIT, (c) 2020 Ross Nichols (Lib/LibSerialize-1.0.0/LICENSE).
  - LibDeflate: LGPL-3.0-or-later (Lib/LibDeflate/LibDeflate.lua:9, README.md:193). The repo's LICENSE.txt is the GPLv3 text.
  - Ace3 libraries: their usual permissive licences. **[not re-checked]**
- A clean-room implementation is advisable: write your own codec, or embed LibDeflate and LibSerialize under their own licences.


---

# Part 2 — Nova World Buffs


Source: `/home/user/watchingmachine/nova-src/NovaWorldBuffs/` (read-only analysis, nothing executed).
Paths below are relative to that folder. Unless stated otherwise, "Data.lua" means `Modules/Data.lua` and "NWB.lua" means `NovaWorldBuffs.lua`.
**[UNCERTAIN]** marks places where I inferred behaviour without a hard proof in the code.

---

## 0. TL;DR

* Prefix **`NWB`**, sent through **AceComm-3.0** (multipart, ChatThrottleLib). The receiver is `NWB:OnCommReceived` (Data.lua:58).
* Every message goes through this pipeline: `S = "<cmd> <ver> <level>[-<layerNum>] <k> <payload>"` → `LibSerialize:Serialize(S)` → `LibDeflate:CompressDeflate(…, {level=9})` (raw DEFLATE) → `EncodeForWoWAddonChannel` (GUILD/PARTY/RAID/WHISPER/CHANNEL) or `EncodeForWoWChatChannel` (YELL/SAY) → `SendCommMessage("NWB", …)`.
* For `data`/`settings`/`requestData`/`requestSettings`, `<payload>` is itself a **LibSerialize** blob of a table whose keys have been shortened, so the table is serialized twice in total.
* `<k>` is an anti-forgery token that changes over time. The receiver rejects timer data whose token doesn't match its own.
* On the TBC client (Interface 20506, after the prepatch) a sender must claim version ≥ **3.26**, and must be level > 5 for any non-guild data and for all top-level data.

---

## 1. Prefixes, transport and priority

| Prefix | Registered | Transport | Use |
|---|---|---|---|
| `NWB` | `NWB.commPrefix = "NWB"` (NWB.lua:15), `self:RegisterComm(self.commPrefix)` (NWB.lua:355) | AceComm-3.0 (addon object created with the AceComm mixin, `Modules/DB.lua:9`) | All NWB traffic |
| `D4C` | `self:RegisterComm("D4C")` (NWB.lua:5092) | AceComm | Listen-only parse of DBM. `parseDBM` returns immediately on layered realms (NWB.lua:5130-5133), so it is **dead on TBC**. |
| `NIT` | `C_ChatInfo.RegisterAddonMessagePrefix("NIT")` (NWB.lua:5094) | **raw** `C_ChatInfo.SendAddonMessage` | Sent only by a group leader when NovaInstanceTracker is not loaded. Payload is the same pipeline applied to the string `"instanceResetOther 0 <instanceName>"`, with no AceComm framing (NWB.lua:5096-5125). Not relevant to timers. |

* **Priority:** `NWB:sendComm` (Data.lua:324-367) accepts a `prio` argument but calls `NWB:SendCommMessage(NWB.commPrefix, data, distribution, target)` without it (Data.lua:366). Every NWB message therefore goes out at AceComm's default **"NORMAL"**, including the logon request whose call site says "ALERT" (NWB.lua:2908).
* **AceComm framing (Lib/AceComm-3.0, MINOR 14):**
  * A message of 255 bytes or less is sent as-is.
  * If it starts with a byte in `\001-\009`, it gets a `\004` prefix (or is forced to multipart if that would exceed 255).
  * Longer messages are split into 254-byte chunks marked `\001` (first), `\002` (middle) and `\003` (last).
  * The receiver reassembles per `prefix\tdistribution\tsender`, with `sender = Ambiguate(sender,"none")`.
  * ChatThrottleLib v31: MAX_CPS 800, BURST 4000, retries on `AddonMessageThrottle`.

## 2. Channels and when they are used

No custom chat channel is joined. `CHANNEL` is supported in `sendComm` but never used, and WHISPER is never used for NWB data.

| Trigger | What is sent | Ref |
|---|---|---|
| `PLAYER_LOGIN` + 0.01 s | `requestData` → GUILD | NWB.lua:2908 |
| Joined a guild (system message) | `requestData` → GUILD | NWB.lua:3031-3035 |
| Received `requestData` (GUILD) | If you are one of the **first 2 online addon users in alphabetical order**, a full `data` reply; otherwise only `settings` | Data.lua:288-294, 443-472 |
| Received `requestSettings` (GUILD) | `settings` | Data.lua:295-298 |
| First `PLAYER_ENTERING_WORLD` + 30 s | `data` → YELL (yellPercent = 100, so effectively always; skipped as a ghost or inside an instance) | NWB.lua:2958-2973 |
| Later `PLAYER_ENTERING_WORLD` + 2 s | `data` → YELL if more than 60 s since the last logon yell | NWB.lua:2980-2990 |
| `TakeTaxiNode`, and again on landing (polled every 2 s) | `data` → YELL | NWB.lua:3143-3168 |
| Periodic | `data` → YELL every 600 s (900 s on CN/TW/KR, **1200 s on layered realms, so TBC**). Not in BG/arena/instance. | Data.lua:2226-2249 |
| `GROUP_JOINED` (more than 60 s after load) + 5 s | `data` → RAID or PARTY (no layermap) | NWB.lua:2998-3013 |
| New timer seen or received | `data` → GUILD and/or YELL (many call sites, e.g. Felwood.lua:431, WorldBuffs.lua:1356, Data.lua:4140) | |
| New data received from a non-guild sender | Re-broadcast `data` → GUILD (relay) | Data.lua:2085-2094 |
| Current layer changed | `l` → GUILD | Data.lua:598-620 |
| Terokkar → Shattrath | `data` (type "terokkar") → YELL after 14 s | Data.lua:3875-3885 |

**Hard blocks on send** (`sendComm`, Data.lua:328-341):
* Nothing is sent to yourself.
* GUILD is skipped if you are not in a guild.
* Only GUILD is allowed in a battleground or arena.
* Only GUILD is allowed in an LFG instance group (INSTANCE_CHAT is never used).
* `sendData` to YELL is skipped inside instances (Data.lua:394).

## 3. Encode and decode pipeline

### 3.1 Outgoing (Data.lua:324-367 plus the per-command builders)

```
S        = cmd .. " " .. VER .. L .. " " .. K .. " " .. payload
ser      = LibSerialize:Serialize(S)                       -- a *string* value
comp     = LibDeflate:CompressDeflate(ser, {level = 9})    -- raw DEFLATE, no zlib header
wire     = (dist=="YELL" or dist=="SAY") and EncodeForWoWChatChannel(comp)
                                         or EncodeForWoWAddonChannel(comp)
AceComm:SendCommMessage("NWB", wire, dist, target)
```

* **`VER`** is the module-level `version = version .. " " .. NWB.i` (Data.lua:384), where `NWB.i = UnitLevel("player")` is captured at file load (NWB.lua:6270). It is therefore **two space-separated tokens**, e.g. `"3.42 70"`.
* **`L`** comes from `getStatusL` (Data.lua:370-381). It is appended directly to the level token, and only for GUILD on layered realms when the `guildL` option is on (default true, Options.lua:2038). It is `"-<currentLayerNumber>"`, or `"-0"` on the first send. Only `data` and `settings` use it. `l` messages always add `"-" .. layerNum`.
* **`K`** is `NWB.k()` (NWB.lua:8033-8036), an anti-forgery token the author deliberately hides in obfuscated code. It is **not documented here**: see "Broadcasting to NWB" at the top of this file.
* **Compression:** any valid raw DEFLATE stream decodes; byte-identical compression is **not** required. LibDeflate 1.0.1, LGPL-3 (`Lib/LibDeflate/LibDeflate.lua:86,9`).
* **Addon-channel codec** (`CreateCodec("\000","\001","")`, LibDeflate.lua:3073-3075): `0x00 → 0x01 0x02`, `0x01 → 0x01 0x03`, and nothing else changes. On decode, the presence of a raw `0x00` means failure.
* **Chat-channel codec** (LibDeflate.lua:3127-3136):
  * Reserved bytes: `s S \000 \n \r | %` and `0x80-0xFF`. Escape bytes: `\029`, `\031`. Map: `s→\015`, `S→\020`.
  * Every other reserved, escape or map byte, in the order `\000 \n \r | %`, `0x80…0xFF`, `\029 \031 \015 \020`, becomes `<esc><r>`.
  * `r` walks upward from 0 over bytes **not** in the taken set {0,10,13,15,20,29,31,37,83,115,124,128-255}, giving 1,2,3,4,5,6,7,8,9,11,12,14,16,…
  * After 127 the escape switches from `\029` to `\031` and `r` restarts at 1.
  * Concretely: `\000→1D 01`, `\n→1D 02`, `\r→1D 03`, `|→1D 04`, `%→1D 05`, `0x80→1D 06` … `0xEF→1D 7F`, `0xF0→1F 01` … `0xFF→1F 13`, `\029→1F 15`, `\031→1F 16`, `\015→1F 17`, `\020→1F 18`.
  * Decode fails if any reserved byte appears raw.
* **LibSerialize** (embedded `Lib/LibSerialize-1.0.0`, MINOR 4, MIT, default options `stable=false`): the version byte `0x01` is followed by objects. A string of length < 16 is the type byte `len*16+2` followed by the bytes. Length < 256 is `0x70 len8`; length < 65536 is `0x78 len16be` (LibSerialize.lua:1043-1067, 766-830). Strings longer than 2 bytes and tables are reference-tracked. **Recommendation:** embed LibSerialize rather than re-implement it. Its table key order is not deterministic in NWB either, so byte-identity is impossible and unnecessary.

### 3.2 Incoming (Data.lua:58-305)

1. Guild bookkeeping: any GUILD message on `NWB` sets `NWB.hasAddon["Name-Realm"]="0"` (Data.lua:62-71, also NWB.lua:3040-3051).
2. Non-GUILD messages are dropped in a BG or arena (Data.lua:72).
3. Own messages are dropped (Data.lua:79-83).
4. If the sender carries a realm suffix and that realm is neither `NWB.realm` nor connected, the message is dropped (Data.lua:96-103).
5. Non-GUILD messages are dropped if `#nwb6` is set, or during the first 10 s after login (`checkedGuildNote`) (Data.lua:109, NWB.lua:1588-1593).
6. Decode with the chat codec for YELL/SAY, otherwise the addon codec. Then `DecompressDeflate`, then `LibSerialize:Deserialize`. If deserialization fails, AceSerializer-3.0 is tried as a legacy fallback (Data.lua:119-140). Nothing marks a message as compressed or uncompressed: everything is compressed, and a failed decode is silently dropped.
7. `args = explode(" ", S, 4)` (NWB.lua:3890) splits **at the first 4 spaces only**:
   * `args[1]` is the cmd and `args[2]` the version.
   * `args[3]` is the level, optionally followed by `-<layerNum>`. The receiver stores the level in a module variable named `time` and the layer in `NWB.hasL[sender]`.
   * `args[4]` is K, stored in a variable named `elapsed`.
   * `args[5]` is the payload, which may contain spaces and binary.
   * The message is dropped if `args[3]` is missing (Data.lua:144-155).
8. Version gating (§5), then dispatch on the cmd (§4).

**Payload table post-processing:**

* `NWB:convertKeys(t, shorten, dist)` (Data.lua:2419-2465) maps keys recursively with the `shortKeys` table (Data.lua:2259-2337). On a YELL receive it also accepts base36-hashed timestamps for `hashKeys` (Data.lua:2374-2409). Senders never hash (that code is commented out), so **send plain numbers**.
* Every converted table then passes through `NWB:config` (`Modules/Options.lua:3967-4025`), an anti-tamper filter:
  * **(a)** In each table, consider numeric values > 50 under string keys that do not contain "Yell". If two such keys share the same value, **every key with that value is set to 0** (Yell keys included).
  * **(b)** Keys matching `r%d` (in practice `flowerN` and `tuberN`) are indexed by timestamp. If more than one pair has consecutive-second timestamps, all of them are zeroed.
  * **Never put identical timestamps on two fields of the same table** (e.g. `lastSeenNPC == terokTowersTime`).

## 4. Message types

All rows below are `S` strings before serialization. Example values: `K="12ept"`, level 70.

| cmd | Sender fn | Payload after K | Accepted on | Effect |
|---|---|---|---|---|
| `data` | `sendData` Data.lua:389-413 | LibSerialize(table) | any | `receivedData` |
| `settings` | `sendSettings` Data.lua:475-491 | LibSerialize({["Name-Realm"]=settings}) | any (stored only from GUILD) | `receivedData` + `extractSettings` |
| `requestData` | `requestData` Data.lua:744-768 | LibSerialize(table) | GUILD | merge, then reply with `data` (top 2) or `settings` |
| `requestSettings` | Data.lua:771-786 | LibSerialize(settings) | GUILD | merge, then reply with `settings` |
| `drop` | Data.lua:640-649 | `<type>[ <layerNum>]` | GUILD/PARTY/RAID | "buff dropped" alert / guild chat (`doBuffDropMsg`, WorldBuffs.lua:1778) |
| `yell` (`yell2`) | Data.lua:651-680 | `<type>[ <layerNum or 0>[ <arg>]]` | GUILD/PARTY/RAID | NPC first-yell warning (`doFirstYell`, WorldBuffs.lua:1623). `sharedLayerBuffs=true` forces layer to nil (Data.lua:661). `arg` is a delay such as `"50"` (zan). |
| `npcKilled` (`npcKilled2`) | Data.lua:683-689 | `<ony\|nef>[ <layerNum>]` | GUILD/PARTY/RAID | `doNpcKilledMsg` |
| `flower` (`flower2`) | Data.lua:692-698 | `<flowerN>[ <layerNum>]` | GUILD/PARTY/RAID | `doFlowerMsg` (Felwood.lua:472) |
| `npcWalking` | Data.lua:717-723 | `<ony\|nef>[ <layerNum>]` | GUILD | `doNpcWalkingMsg` (NWB.lua:9917) |
| `handIn` | Data.lua:701-707, sent on YELL by `questTurnedIn` (NWB.lua:1943-1949) | `<questID>` (4974 rend, 7491/7496 ony, 7784/7782 nef, 8183 zan) | **not** GUILD/PARTY/RAID (YELL) | "X is being handed in" notice (WorldBuffs.lua:1906) |
| `l` | `sendL` Data.lua:598-620 | none (zoneID/buff list only on Wrath) — the layer number travels as `"70-<layerNum>"` in the level slot | GUILD | `hasL[sender]=layerNum` (guild layer roster) |
| `lb`, `rlb` | Data.lua:531-553, 3740 | — | GUILD | **disabled** (bodies commented out) |
| `stvb` | Data.lua:710-715 | `<zoneID> <x> <y>` | GUILD/PARTY/RAID | SoD only |
| `versionList` | NWB.lua:3928-3940 | `"0 0 " .. LibSerialize(table)` | — (no handler) | YELL; sent only by the odd `isClassicCheck` self-test (char "Hi" on realm "There :)", NWB.lua:5951, 8273). Ignore. |

Type tokens: `rend`, `rendCrossroads`, `ony`, `nef`, `zan`, `flower1`…`flower10`. A **`layerNum` here is the 1-based ordinal of the layer** in the sender's sorted layer list, not a zoneID. It is only meaningful when both clients know the same layer set.

Examples:
* `"drop 3.42 70 12ept ony 2"`
* `"yell 3.42 70 12ept zan 0 50"`
* `"l 3.42 70-2 12ept"`
* `"handIn 3.42 70 12ept 7491"`

### 4.1 The `data` table

The table is built by `createDataLayered` (Data.lua:922-1269) on layered realms (**TBC is always layered**), or by `createData` (Data.lua:789-918). It is shortened by `convertKeys` before serialization.

Top level:
* `layers` — a literal key: `{ [zoneUID:number] = layerTable }`.
* Non-layered `flowerN` timers (only when `layeredSongflowers` is false — never on TBC).
* `tuberN` (SoD only).
* TBC/Wrath dailies:
  * `tbcHD`/`tbcHDT` (O/P): heroic daily id (`NWB.heroicDailies[questID].id`) and the time it was seen.
  * `tbcDD`/`tbcDDT` (Q/R): normal dungeon daily.
  * `tbcPD`/`tbcPDT` (S/T): PvP daily.
  * Each is sent only if seen within 86400 s (Data.lua:1207-1226). The TBC quest→id tables are at Data.lua:4931-5236.
* Wrath only: `wintergrasp` (W), `wintergraspTime` (Y), `wintergraspFaction` (X).
* GUILD only: `["Name-NormalizedRealm"] = settingsTable`.
* `timerLog` (F) — Classic/TBC-prepatch only, **not on TBC now**.

`layerTable` (only keys with live data are included):

| Long key | Short | Meaning |
|---|---|---|
| `rendTimer`/`rendYell` | n/o | Buff drop time / NPC first-yell time (epoch s). The yell must be within ±120 s of the timer. |
| `onyTimer`/`onyYell` | s/t | same |
| `nefTimer`/`nefYell` | y/z | same |
| `onyNpcDied`/`nefNpcDied` | x/D | NPC killed (nef only sent by Alliance) |
| `flower1..10` | f1..f10 | Songflower pick time (respawn 1500 s) |
| `terokTowers` | L | Epoch when the Terokkar towers reset (future) |
| `terokTowersTime` | U | Epoch when that reading was taken |
| `terokFaction` | M | 1 neutral, 2 Alliance, 3 Horde (Data.lua:3991-3999) |
| `lastSeenNPC` | E | Last time a layer-defining NPC was targeted. **Required for the receiver to accept the layer.** |
| `spawn` | af | Earliest NPC spawn epoch derived from the GUID spawnUID (layer age) |
| `layerMap` | (literal) | `{ [zoneUID] = uiMapID }` — other zones' creature zoneUIDs known to belong to this layer. Fewer than 70 entries; sent at most every 1840 s per channel or 3600 s per layer, never to PARTY/RAID. |

Settings table (Data.lua:1398-1424):
* Keys: `a` disableAllGuildMsgs, `b` guildBuffDropped, `c` guildNpcDialogue, `d` guildZanDialogue, `e` guildNpcKilled, `f` guildSongflower, `g` guildCommand, `j` guild10, `l` guild1, `K` guildNpcWalking, `V` guildTerok10 (non-Classic only).
* Values are 0/1. Defaults are 1, except `a` which defaults to 0 (Options.lua:1896-1917).

**Example (TBC, GUILD) before shortening:**
```lua
{ layers = { [11872] = { lastSeenNPC=1792003500, spawn=1791950112,
                         terokTowers=1792010040, terokTowersTime=1792003020, terokFaction=3,
                         layerMap = { [11873]=1944, [11879]=1955 } } },
  tbcHD = 7, tbcHDT = 1791990000,
  ["Watcher-Spineshatter"] = { a=1,b=0,c=0,d=0,e=0,f=0,g=0,j=0,l=0,K=0,V=0 } }
```
After shortening it becomes `{layers={[11872]={E=…,af=…,L=…,U=…,M=3,layerMap={…}}}, O=7, P=…, ["Watcher-Spineshatter"]={…}}`. The message is then `S = "data 3.42 70-1 12ept " .. LibSerialize(shortTable)`.

### 4.2 Layers (how they are identified)

* A layer ID is the **zoneUID**: the 5th `-` field of a Creature GUID, `Creature-0-srv-inst-ZONEUID-npcID-spawnUID`.
* On TBC it is taken from one of the Shattrath (uiMap 1955, `NWB.map`) NPCs A'dal 18481, Nutral 18940, Minalei 19046 or Innkeeper Haelthol 19232 (Creatures.lua:541-546, 883-888; NWB.lua:7868-8000).
* Other zones are tied to a layer through `layerMap`. The TBC whitelist is SW 1453, Org 1454, Hellfire 1944, Zangarmarsh 1946, Shadowmoon 1948, Blade's Edge 1949, Nagrand 1951, Terokkar 1952, Netherstorm 1953, Shattrath 1955 and Quel'Danas 1957 (NWB.lua:97-120).
* On TBC: `limitLayerCount = 20` (NWB.lua:82-85), `layerExpireTime = 7200` (NWB.lua:60-63), and a layer expires with no valid timer once it is `created` + 7200 s old (NWB.lua:6588-6640).

## 5. Version gating

* The receiver ignores any version < 1.83 (Data.lua:166-174). Below 1.50 it only answers `requestData` (Data.lua:185-197).
* The `drop`/`yell`/`npcKilled`/`flower`/`npcWalking`/`l`/`stvb` block only needs ≥ 1.50 (Data.lua:205-238).
* `data`, `settings`, `requestData` (merge), `requestSettings` and `handIn` need a per-flavour minimum: **TBC 3.26**, MoP megaserver 3.16, MoP 3.11, other flavours 2.75. Below that, only `requestData` gets a reply (Data.lua:240-284).
* `versionCheck` (Data.lua:307-319): if the remote version is higher than the local one on GUILD/PARTY/RAID, the user sees an "out of date" print at most every 4 h, and `latestRemoteVersion` is updated. **Do not claim a version above the real NWB release** (use `3.42`).
* `NWB.hasAddon[sender] = remoteVersion` feeds the guild-message election. A `minVersion` filter is used for some messages, e.g. 2.37 for a Terokkar message (NWB.lua:1252).

## 6. Validation and trust on receive

* **Who:** anyone on the same or a connected realm, on any channel, unless `#nwb6` or the user option `receiveGuildDataOnly` is set (flowers are exempt when `syncFlowersAll` is on). There is a blacklist `lst` (Data.lua:727-743), currently empty.
* **Anti-forgery gates:**
  * `self.j(elapsed)` (NWB.lua:6427-6432) requires the sender's anti-forgery token to match the receiver's own. It gates both the layered loop (Data.lua:1597) and the top-level loop (Data.lua:1882). A mismatched message is silently dropped.
  * The layered loop also needs `isClassic or GUILD or level>5`. The top-level loop needs `isClassic or level>5`, **with no GUILD exemption**.
* **World-buff timers:** the timer needs a Yell field within ±120 s. A top-level timer must be ≥ the local value; a layered timer must be within its cooldown. Identical timestamps across layers are dropped (Data.lua:1567-1594, 1628-1665, 1678-1709; `validateData` Data.lua:2199).
* **Generic numeric merge:**
  * **newest wins**: `v > local and v ~= 0` (not per-sender).
  * `validateTimestamp` (NWB.lua:1882-1902): ≤ 2585912598, ≤ now+30000, and respects the `noOverwrite` option.
  * Top-level caps: flower/tuber/dragon ≤ now+1530; ony ≤ now+21660; nef ≤ now+28860; rend ≤ now+10860 (Data.lua:1977-1985).
  * Exceptions: `lastSeenNPC` newer-only, `spawn` **older-only**, `created` keep-first (Data.lua:1780-1813).
  * `validateCloseTimestamps` (Data.lua:1348-1396) rejects a value within ±30 s (±10 s for flowers) of the same key on another layer. It is skipped for rendTimer and terok keys.
* **Terokkar:** accepted only if `terokTowersTime` is newer than the local one and within ±21700 s of now, the tower value is in (now, now+21700), and it is > local − 1800 (Data.lua:1720-1756, 1932-1958).
* **Layer acceptance** (Data.lua:1600-1625):
  * Keys must be numbers.
  * `lastSeenNPC` must be present and < 7200 s old on TBC.
  * The layer must not be disabled locally.
  * An unknown layer is **created** (`createNewLayer(layer,"other")`, NWB.lua:6435) up to the layer cap.
* **layerMap merge** (Data.lua:1833-1855): an entry is added only if mapID is whitelisted, the zoneUID is unknown in every layer, and `validateZoneID` passes (NWB.lua:8243-8271).
* **Dangerous permissive path:** unknown keys with **table** values, and valid keys with non-numeric values, are written verbatim into `NWB.data[k]` / `NWB.data.layers[layer][k]` (Data.lua:1856-1869, 2064-2075). Sending a key such as `myChars` would overwrite saved variables. **Never send keys outside `validKeys` (Data.lua:1427-1492).**
* **Relay:** new data from a non-guild sender is pushed to the receiver's guild (Data.lua:2085-2094). Any bad data you yell gets amplified.

## 7. Throttling

* **Send side:**
  * `sendL` ≥ 10 s apart (Data.lua:599-603).
  * YELL ticker every 1200 s (TBC).
  * Logon yell guard of 30–60 s.
  * Layermap every 1840 s per channel and 3600 s per layer.
  * Terokkar sends ≥ 175 s apart (layered) or 1800 s (unlayered) (Data.lua:4140, 4166).
  * `versionList` ≥ 60 s apart.
  * Group sync only if more than 60 s after load.
  * `rlb` 5 s.
  * Below all of this, ChatThrottleLib (800 CPS).
* **Receive side:** there is **no per-sender rate limit**. Only UI cooldowns apply: `!wb`/`!dmf` 5 s (NWB.lua:1679-1693), drop/yell alerts 40 s, flower msg 10 s, npcDied notice 600 s, "has new data" for terok 300 s.
* **Your risk:** every `requestData` on GUILD makes **every** online NWB user reply (2 with full data, the rest with settings). Send at most one per login. Blizzard's server-side addon-message throttle applies to your prefix use; CTL retries on `AddonMessageThrottle` (ChatThrottleLib.lua:347-379).

## 8. Guild flags `#nwb1`..`#nwb8` (NWB.lua:1598-1677)

* **Where they are read:** the *public note* of the first roster entry with rankIndex 0 (the GM), **or** the guild info text. The match is lowercased and uses `string.find` with no plain flag (`#` is not magic).
* **When:** at logon + 10 s and on every `GUILD_ROSTER_UPDATE`.
* **Effect:** they **only suppress guild-chat (SendChatMessage) posts**, except for #nwb6:

| Flag | Effect |
|---|---|
| #nwb1 | All NWB guild chat messages |
| #nwb2 | Timer warnings (guild30/15/10/5/1/0, guildTerok10) |
| #nwb3 | Buff-dropped, NPC dialogue and Zandalar dialogue messages |
| #nwb4 | `!wb`/`!dmf` replies |
| #nwb5 | Songflower messages |
| #nwb6 | **Receive:** ignore all non-GUILD addon data (`NWB.guildDataOnly`, Data.lua:109) |
| #nwb7 | Bug: the table has `["#nwb7"]` twice, so the second (`=8`) wins. `#nwb7` therefore disables **NPC walking** messages, and NPC-killed (7) can't be disabled. |
| #nwb8 | Not recognised (no effect) |

* **Election:** `sendGuildMsg` (NWB.lua:1462-1578) builds the candidate set from online, non-mobile guild members who are in `hasAddon`. When a `msgType` is given, each candidate also needs a stored settings table (`NWB.data[name]`) with that msgType = 1/true and `a` ≠ 1, or the candidate must be yourself. The **alphabetically first** candidate posts.
* **`!wb` handling** (NWB.lua:1679-1693): a lowercased guild message starting with `!wb` triggers this election (msgType `guildCommand`), and the elected client posts the timers prefixed `!wb`.
* **On TBC** (NWB.lua:1478-1480), `sendGuildMsg` returns unless msgType is `guildTerok10` or `guildWintergrasp10`, so **`!wb`, drop, flower and NPC guild posts never happen**. Only the Terokkar 10-minute warning is posted.

## 9. TBC client specifics (`NWB.isTBC`, Modules/DB.lua:58-63)

* The flavour is detected with `WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC`. `isTBCPrepatch` is true only before 2026-02-04, so it is false now.
* Layered, 20 layers, 7200 s expiry. Layer IDs come from Shattrath NPC zoneUIDs, with the Outland + SW/Org layerMap whitelist.
* **No timer log.** World-buff timers are hidden in the UI (`expansionNum < 2 or prepatch`, NWB.lua:4391). Rend/Ony/Nef are still recorded and synced per layer if they happen; the cooldowns are unchanged at 10800/21600/28800 (DB.lua:91-94). **[UNCERTAIN]** whether these drops still occur meaningfully in TBC Anniversary.
* Rend is attached to a layer only if the layer already exists. Layer creation from a buff GUID is Classic-only (WorldBuffs.lua:1335).
* **What actually matters on TBC:**
  * Terokkar tower timers per layer (Data.lua:3940-4170).
  * Heroic, dungeon and PvP dailies (global).
  * The layer lists themselves (`lastSeenNPC`, `spawn`, `layerMap`).
  * Songflowers per layer. **[UNCERTAIN]** These are rarely shared on TBC, because Felwood (1448) is not in the TBC layerMap whitelist, so a flower can only be attached through the single-layer or logon-backup fallbacks (Felwood.lua:390-404).
* Tubers and dragons are not shared (SoD only). **Darkmoon Faire has no comms** — it is computed locally from dates (DMF.lua; no `sendComm` call sites). DBM parsing is disabled.
* The version floor for data is **3.26**, and the non-guild level gate is `level > 5`.

## 10. Minimum viable interop

**(a) Listen and show NWB timers**
1. Register prefix `NWB` (C_ChatInfo) and handle `CHAT_MSG_ADDON`, with AceComm reassembly (`\001`/`\002`/`\003`/`\004`) keyed by prefix, distribution and sender. Simplest: embed AceComm.
2. Decode with the chat codec for YELL/SAY and the addon codec otherwise. Then raw INFLATE, then LibSerialize → string S.
3. `explode(" ", S, 4)` to get cmd, ver, level[-layer], K and payload.
4. For `data`/`settings`/`requestData`, LibSerialize the payload back into a table and expand the short keys. Read `layers[zoneUID]` (`E`, `af`, `L`, `U`, `M`, `layerMap`, and n/o, s/t, y/z, f1..f10) plus O..T.
5. Apply your own sanity rules: the ±120 s yell rule, the future caps, newest-wins, and `lastSeenNPC` < 7200 s. Ignore K (it's an anti-forgery token; listening doesn't need it).
6. Parse `l` (the guild member's layer number) and `drop`/`yell`/`npcKilled`/`flower`/`npcWalking`/`handIn` for notices.
7. Never answer `requestData`. You are not required to.

**(b) Broadcasting to NWB: not done**

Watching Machine doesn't send to NWB; see "Our decisions" at the top of
this file. Sending would need the author's hidden anti-forgery token, which
isn't documented here. The risks below are why it would also be unsafe for
NWB users.

**Risks**
* **Layer pollution:** if you invent or mis-attribute zoneUIDs, or refresh `lastSeenNPC` without actually seeing a Shattrath NPC, you create or keep phantom layers and wrong layerMaps on every NWB client, and those clients relay to their guilds. Only forward layers you derived from a creature GUID of the four Shattrath NPCs.
* **Data corruption:** unknown table keys and non-numeric values in valid keys are written straight into NWB's SavedVariables.
* **Guild election:** any GUILD send adds you to `hasAddon`, which can push a real NWB user out of the "top-2 responders". If NWB ever stored settings for your character (e.g. you once ran NWB; they are kept 30 days, Data.lua:2607-2616), you could win the Terokkar-warning election and silence it. Mitigation: avoid GUILD sends, or include your settings with `a=1` and everything else 0.
* **Version nag:** don't claim a version above the real one.
* **Throttle/disconnect:** large payloads go multipart. Keep sends rare: at most one YELL per 20 min plus event-driven sends. No `requestData` spam.

## 11. Licence

* NovaWorldBuffs has **no licence statement** in `readme.txt`, `NovaWorldBuffs.toc` or any source header. The headers only credit "Novaspark-Arugal OCE" and a CurseForge URL (NWB.lua:1-4, readme.txt:1-4). Treat it as all rights reserved; this spec describes the format, not their code.
* Embedded libraries:
  * LibSerialize: MIT, © 2020 Ross Nichols (`Lib/LibSerialize-1.0.0/LICENSE`).
  * LibDeflate 1.0.1: LGPL-3.0-or-later, © Haoqian He (`Lib/LibDeflate/LibDeflate.lua:9`, README.md:193). The bundled LICENSE.txt is the GPLv3 text that LGPL builds on.
  * Ace3 libraries: under their own (BSD-style) licences — not inspected.

---

# Part 3 — Nova World Buffs features on TBC (what World Timers follows)

How NWB behaves on the TBC client for the features Watching Machine's World
Timers module mirrors (`Modules/WorldTimers.lua`, 3.28). It extends Part 2.
One correction to Part 2: the ±30 s "close timestamps" check is *skipped*
for `rendTimer`, `terokTowers` and `terokFaction`, and it also compares
against the target layer itself.

Source: Nova World Buffs 3.42, read-only analysis of `/home/user/watchingmachine/nova-src/NovaWorldBuffs/`.
This spec extends `docs/NOVA-PROTOCOL.md` Part 2 (transport, codecs, gating) and does not repeat it.

**Path conventions**
- `NWB.lua` means `NovaWorldBuffs.lua`.
- `Data.lua`, `DMF.lua`, `WorldBuffs.lua`, `Felwood.lua`, `Options.lua`, `DB.lua` and `Creatures.lua` are under `Modules/`.
- `enUS` means `Locale/enUS.lua`.

**Markers**
- **[TBC]** marks the branch that runs when `NWB.isTBC` is set (and `isClassic`, `isSOD` and `isWrath` are not).
- **[UNC]** marks an inference that the code doesn't prove.

**TBC flags that matter everywhere**
- Flavour detection (DB.lua:58-63):
  - `isTBC = (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)`.
  - `expansionNum = 2`.
  - `isTBCPrepatch` is true only before 1770220800 (2026-02-04), so it is **false** now.
- Layering (NWB.lua:52-90):
  - `isLayered = true`, `layerExpireTime = 7200`, `limitLayerCount = 20`.
  - `sharedLayerBuffs = true` and `doLayerMsg = false` (NWB.lua:23-24).
- Cooldowns stay at rend 10800, ony 21600, nef 28800 (DB.lua:91-94). Only Classic sets `nefCooldownTime = 0` (DB.lua:119-120).
- `noWorldBuffTimers` and `noDmfCooldown` are nil on TBC; only SoD and Forever set them.
- Saved data `NWB.data` is `db.global[realm][faction]` (Options.lua:2207), so everything below is **per realm and per faction**.

---

## 1. Darkmoon Faire

DMF on TBC is computed locally from the calendar date. It has no comms and no calendar API use: `getNextDmfCalender` is only used by the final `else` branch, which is for later expansions (DMF.lua:616-624).

### 1.1 Start/end computation (`getDmfStartEnd`, DMF.lua:236-494; TBC uses the non-SoD branch at 292-493)

**Region.** `NWB:GetCurrentRegion()` (NWB.lua:413-422) uses `C_BattleNet.GetGameAccountInfoByGUID(UnitGUID("player")).regionID`, falling back to `GetCurrentRegion()`. The IDs are 1 US (also OCE), 2 KR, 3 EU, 4 TW, 5 CN.

**Offsets** (`dayOffset` counts days after the first Friday; `hourOffset` is a UTC hour):

| Condition | dayOffset | hourOffset |
|---|---|---|
| realm ∈ {Arugal, Felstriker, Remulos, Yojamba} (OCE Era names) | 2 | 18 |
| realm ∈ {Arcanite Reaper, Old Blanchy, Anathema, Azuresong, Kurinnaxx, Myzrael, Rattlegore, Smolderweb, Thunderfury, Atiesh, Bigglesworth, Blaumeux, Fairbanks, Grobbulus, Whitemane} (US-West) | 2 | 11 |
| region 1 (otherwise) | 2 | 8 |
| region 2 (KR) | 3 | 1 |
| region 3 (EU) | 3 | 2 |
| region 4 (TW) | 3 | 1 |
| region 5 (CN) | 2 | 20 |

- Any other region is not "validRegion", so the function returns nil and you get no timer.
- **[UNC]** None of the TBC Anniversary realm names are in these lists, so on TBC every US and OCE realm uses the region 1 row and every EU realm uses the region 3 row. OCE is probably shown wrong; the author notes such a bug at DMF.lua:235.

**Algorithm** (DMF.lua:348-493; `t = GetServerTime()`):
1. If the client's **local OS time** says DST (`date("*t", t).isdst`), then `hourOffset = hourOffset - 1` (DMF.lua:349-353).
2. Take the year and month from `date("!*t", t)`, or the caller-supplied month and next year (DMF.lua:355-361).
3. `firstFriday` = the first day i in 1..7 where `date("%w", time({year, month, day=i})) == "5"` (DMF.lua:390-400).
4. `timeTable = {year, month, day = firstFriday + dayOffset, hour = hourOffset, min = 0, sec = 0}`.
5. `dmfStart = time(timeTable) - secondsDiff`, where `secondsDiff = difftime(time(utcdate), time(localdate with isdst=false))` (DMF.lua:408-421). The net effect is that `timeTable` is interpreted as **UTC**, with a ±3600 artefact when DST status differs between now and the target date.
6. If `date("%w", dmfStart) == "0"` (Sunday in local time), then `dmfStart = dmfStart + 86400` (DMF.lua:471-476). For the region 1 row this turns "Fri+2 = Sunday 08:00 UTC" into **Monday 08:00 UTC** (Monday 03:00 or 04:00 US Eastern, i.e. daily reset).
7. `dmfEnd = dmfStart + 604800` (7 days) (DMF.lua:478).

`staticDmfDates` is empty on TBC (DMF.lua:101-119), so the static-date and recalc branches never trigger.

Effective rule for a clean implementation:
- **DMF starts on the Monday after the first Friday of the month, at the region's daily-reset hour**, and lasts 7 days.
- EU: Monday 02:00 UTC, or 01:00 UTC if the local clock is in DST. The comment says this is meant to be 04:00 server time.
- US: Monday 08:00 UTC, or 07:00 UTC in DST.

### 1.2 State (`getDmfData`, DMF.lua:539-615, `isClassic or isTBC` branch)

- `t < start`: `type = "start"`, timestamp = start, `NWB.isDmfUp = nil`.
- `t < end`: `type = "end"`, timestamp = end, `isDmfUp = true`.
- `t > end`: recompute for next month (December rolls to January of next year), `type = "start"`.
- Returns `(timestamp, timeLeft, type)`.

### 1.3 Location (DMF.lua:568-612)

- `startMonth = tonumber(date("%m", dmfStart))`. If the start day is > 20, `startMonth` is incremented.
- **[TBC] "different in anni"** (DMF.lua:583-590):
  - months 1/4/7/10 → `"Outlands"` (Terokkar Forest, near Shattrath)
  - months 3/6/9/12 → `"Elwynn Forest"`
  - months 2/5/8/11 → `"Mulgore"`
- The same rule gives the "next location": it is computed for whichever start is next.
- Display names:
  - `L["Outlands"]` is **missing in enUS**, so AceLocale returns the key "Outlands".
  - `L["mulgore"]` = "Mulgore", `L["elwynnForest"]` = "Elwynn Forest" (DMF.lua:627-635).

### 1.4 Map markers (`refreshDmfMarkers`, DMF.lua:839-861)

Pins use HereBeDragons, and are drawn only if `showDmfMap` is set (default true, Options.lua:1932).

| Zone | Zone pin (map, x%, y%) | Continent pin (map, x%, y%) |
|---|---|---|
| Outlands | 1952 Terokkar, 34.8, 34.6 | 1945 Outland, 44.6, 69.5 |
| Mulgore | 1412, 36.8, 37.6 | 1414 Kalimdor, 45.95, 59.6 |
| Elwynn | 1429, 42, 70 | 1415 Eastern Kingdoms, 45.2, 73.55 |

- The zone pin icon is 23 px, the continent pin 14 px, both using `Media\dmf`. The continent pins are deliberately placed 1 coordinate south of the real spot.
- Pin label:
  - "Starts in 3h4m" or "Ends in …", using the short time format.
  - "No timer" if there is no timestamp.
- Pin tooltip, in order:
  - "Darkmoon Faire"
  - "Starts in / Ends in <long time>"
  - full date
  - if DMF is up: "Your DMF buff cooldown has %s left." or "Your Darkmoon Faire buff is off cooldown." (DMF.lua:691-746)
- `/dmf map` opens 1952, 1412 or 1429 depending on the zone (DMF.lua:23-33).

### 1.5 Sayge's fortune cooldown

**Detection** (WorldBuffs.lua:928-950):
- CLEU `SPELL_AURA_APPLIED` or `SPELL_AURA_REFRESH` with `destName == UnitName("player")` and a spellID in the DMF set:

| SpellID | Fortune |
|---|---|
| 23768 | Damage |
| 23769 | Resistance |
| 23767 | Armor |
| 23766 | Intelligence |
| 23738 | Spirit |
| 23737 | Stamina |
| 23735 | Strength |
| 23736 | Agility |

- The buff's remaining duration must be ≥ 7199 s. That makes it a fresh 2 h buff, which rules out logon re-application.
- Then `trackNewBuff(name, "dmf")` → `addDmfCooldown()`.

**Cooldown handling:**
- `addDmfCooldown()` sets `NWB.data.myChars[charName].dmfCooldown = 14400` (**4 h**; NWB.lua:2168-2174).
- It prints `L["dmfBuffDropped"]`: "Darkmoon Faire buff %s received, to track the 4 hour ingame cooldown for this buff type /buffs." (NWB.lua:2104-2110).
- Countdown: the 1 s ticker (`NWB:ticker`, re-armed by `C_Timer.After(1)`, NWB.lua:1279) does `dmfCooldown = dmfCooldown - 1` **only while logged in** (NWB.lua:1216-1227). It is a played-time countdown, not wall-clock.
- When it crosses from ≥1 to ≤0 while DMF is up, NWB prints "Your Darkmoon Faire buff cooldown has reset."
- `-99999` is the sentinel for "reset", and is never shown.
- `getDmfCooldown()` returns `dmfCooldown, dmfCooldownNoMsgs` (NWB.lua:2151-2166).

**[TBC] reset paths that do not apply:**
- `checkDmfBuffReset` (offline more than 8 days, or more than 8 h while rested, DMF.lua:637-689) returns immediately unless `isClassic`.
- `countDebuffs` (debuff-cap reset) runs only for `isClassic` (WorldBuffs.lua:753).
- On TBC the cooldown therefore simply counts down 14400 online seconds.
- **[UNC]** The string `dmfBuffCooldownMsg3` ("also resets with the weekly server reset") is display-only, and no code implements a weekly reset.

**DMF-related user messages on TBC:**
- At logon or on `/wb`, the cooldown line is printed if DMF is up and the cooldown is > 0 (`logonDmfBuffCooldown` and `showDmfBuffWb` default true; NWB.lua:613-623).
- The DMF *spawn* line in `/wb` and at logon prints only on Classic (NWB.lua:605-607). On TBC you get it from `/dmf` only.
- `/dmf` prints "Darkmoon Faire spawns in %s (%s)" or "Darkmoon Faire ends in %s (%s)", followed by " (Zone)", then the cooldown or ready line (DMF.lua:38-73).
- The minimap tooltip DMF section is SoD-only (`addDMFMinimapString` returns unless `isSOD`, DMF.lua:876-879).
- On non-Classic clients the Damage fortune's percent is shown via `UNIT_DAMAGE` (WorldBuffs.lua:930-932). This is cosmetic.

---

## 2. Layers on TBC

### 2.1 Identity

- Layer key = **zoneUID**, the 5th `-` field of a `Creature-0-<srv>-<inst>-<zoneUID>-<npcID>-<spawnUID>` GUID.
- **Layer creation** needs the target or mouseover to satisfy all of:
  - in `NWB.map = 1955` (Shattrath, Creatures.lua:883-888)
  - `unitType == "Creature"`
  - npcID ∈ `NWB.npcs = shattrathCreatures` = {18481 A'dal, 18940 Nutral, 19046 Minalei, 19232 Innkeeper Haelthol} (Creatures.lua:541-546)
- Creation happens in `setCurrentLayerText` → `createNewLayer(zoneUID, GUID, true)` (NWB.lua:7999-8012).
- Creation fails if:
  - there are already 20 layers, or
  - the zoneUID is 0, or
  - the GUID's npcID isn't in `npcs` (NWB.lua:6435-6466).
- Excluded "companion" creatures, which are never used for layer detection or mapping (Creatures.lua:548-558): 9662, 187832, 6491 (Spirit Healer), 18483 Empoor's Bodyguard, 18482 Empoor.

### 2.2 Numbering

- Layer N is the N-th key of `NWB.data.layers` in **ascending numeric zoneUID order** (`pairsByKeys` = `table.sort` on the keys, NWB.lua:3910-3926; `GetLayerNum` NWB.lua:3978-3993).
- Clients with different layer sets get different numbers.

### 2.3 Per-layer fields (local)

- `created`, `lastSeenNPC`, `GUID`, `npcID`, `spawn`, `layerMap{}`
- timer fields: rend/ony/nef `*Timer`, `*Yell`, `*Yell2`, `*NpcDied`
- `flower1..10`
- `terokTowers`, `terokTowersTime`, `terokFaction`, `terokTowers10` (warning flag)
- `hellfireRep`

`createNewLayer` initialises the timers to 0 and `flowerN` to 0 (NWB.lua:6467-6494). It restores `layerMap` from `layerMapBackups[zoneUID]` if that is less than 6 days old, skipping the key "created" and any value 1952 (NWB.lua:6498-6512).

### 2.4 Refresh and "spawn"

Targeting or mousing over one of the 4 Shattrath NPCs on a known layer sets `lastSeenNPC = now`, `GUID` and `npcID` (NWB.lua:7926-7938). Conditions:
- in 1955
- more than 600 s since the last group join
- more than 30 s since the last zone change

`spawn` (layer age) comes from the spawnUID, a 10-hex-char string (NWB.lua:7940-7953):
- `epoch = now - (now % 2^23)`
- `offset = tonumber(spawnUID:sub(5), 16) & 0x7fffff`
- `spawn = epoch + offset`; if that is > now, subtract `2^23 - 1`
- Keep the **minimum** value ever seen.
- Shown as "(Active 3d4h)" in the minimap tooltip.

### 2.5 Expiry

- **Every 60 s** (`removeOldLayersTicker`, NWB.lua:6542-6586): delete a layer if `now - lastSeenNPC > 7200`, unless one of `flower1..9` is less than 1500 s old.
- **At load and on some refreshes** (`removeOldLayers`, NWB.lua:6588-6687): delete a layer if it has no valid timer and `created < now - 7200`. Its layerMap is then saved to `layerMapBackups`, which are kept 4 days.
- Valid timers for this check:
  - `rendTimer + 7200 > now - 10800` (and the same form for ony and nef)
  - `terokTowers + 3600 > now`
  - `lastSeenNPC + 7200 > now`

### 2.6 Layer mapping (other zones → layer)

`mapCurrentLayer(unit)` runs on target or mouseover outside Shattrath, and is skipped while on a taxi, in an instance, a BG or an arena (NWB.lua:8047-8236).

- **Whitelist** (NWB.lua:97-120): 1453 SW, 1454 Org, 1944 Hellfire, 1946 Zangarmarsh, 1948 Shadowmoon, 1949 Blade's Edge, 1951 Nagrand, 1952 Terokkar, 1953 Netherstorm, 1955 Shattrath, 1957 Quel'Danas.
- **Current layer**:
  - `NWB.lastKnownLayerMapID`, the Shattrath zoneUID of the layer you're on.
  - It is set when you target any creature whose zoneUID equals a known layer key (in practice, in Shattrath), and more than 180 s have passed since the last group join (NWB.lua:7902-7905).
  - Otherwise it is recovered by finding the creature's zoneUID in some layer's `layerMap` **with the same uiMapID** (NWB.lua:8105-8128).
- **Mapping rules** (a new `layerMap[zoneUID] = uiMapID` entry):
  - Never while `now - lastJoinedGroup < 180`.
  - **On non-Classic, never at all once any group was joined this session** (`lastJoinedGroup > 0`, NWB.lua:8148-8154).
  - Skip the guard NPCs 68 (Horde) and 3296 (Alliance).
  - `phaseCheck`: the first creature in a zone records its zoneUID. A different zoneUID later in the same zone simulates a group join, i.e. the layer is considered lost (NWB.lua:8156-8166).
  - A zoneUID already present in another layer's map resets `lastKnownLayerMapID = 0` (NWB.lua:8174-8191).
  - An already-mapped uiMapID for this layer is never overwritten (NWB.lua:8192-8198).
  - Reject if `|zoneUID - layerKey| > 200` and you haven't confirmed the layer in Shattrath (`lastKnownLayerMapID_Mapping == 0`) (NWB.lua:8200-8213).
  - Reject if the zoneUID is itself a layer key (`validateZoneID`).
  - **Terokkar (1952)** is mapped only with `lastKnownLayerMapID_Mapping > 0`, i.e. a strict Shattrath NPC confirmation this session (NWB.lua:8215-8226).
  - A new mapping immediately triggers `sendData("GUILD")` and `sendData("YELL")` with forced layerMap.
- Joining a group (`GROUP_JOINED` with more than 1 member), or leader `UNIT_PHASE`, resets `lastKnownLayerMapID`, `currentZoneIDStrict` and related state (NWB.lua:7740-7808).

### 2.7 "Which layer am I on" (`recalcMinimapLayerFrame`, NWB.lua:8904-9000)

1. If `lastKnownLayerMapID > 0`, use its ordinal.
2. Else, in Shattrath, use `currentLayer`.
3. Else (backup), if the last creature zoneUID appears in any layer's `layerMap`, use that layer's ordinal (it doesn't check uiMapID).
4. Else "No Layer". The frame is hidden outside Shattrath.

**Events:** `UNIT_TARGET`, `PLAYER_TARGET_CHANGED` (unit "target"), `UPDATE_MOUSEOVER_UNIT` ("mouseover") (NWB.lua:7723-7734). On TBC there are **no nameplate or combat-log sources**; the nameplate scan is Classic-only, NWB.lua:10325.

**UI on TBC:**
- Minimap layer frame "Layer N" (`minimapLayerFrame` default true), with an optional zoneID.
- `/wb` (opens the layer frame) lists `[Layer N] (Shattrath <zoneUID>) (Active …)` with the Terokkar timer per layer, "Last seen: X ago", "Active for: …" and the NPC.
- Strings: "You are currently on [Layer N]." and "Target any NPC to see your current layer."

### 2.8 Guild layer roster ("l")

- Sent by `sendL(ordinal)` (Data.lua:598-620) whenever the shown ordinal changes, at least 10 s apart, only to GUILD, only if in a guild and not in a BG or arena, and only if `guildL` is set (default true).
- The ordinal can be 0 when the layer becomes unknown.
- Wire string: `"l <ver> <lvl>-<ordinal> <K>"`, e.g. `"l 3.42 70-2 12ept"`. There is no payload on TBC; `layerBuffSpells` is empty there.
- **Any** message's 3rd field `lvl-x` sets `hasL[sender] = x` (Data.lua:150-155). That includes `data` and `settings`, which carry `-<ordinal>` on GUILD when `guildL` is set.
- `/wb guild` shows online guild members grouped by ordinal, with their roster zone (Data.lua:3750-3820).
- It is **sender's-ordinal** based, so it is only meaningful if both clients know the same layer set.

---

## 3. Terokkar Forest towers

### 3.1 What it is

The timer is the time until the **Spirit Towers / Bone Wastes PvP objective resets**. This is the "Terokkar Forest towers reset in X" event. The towers are locked for about 6 h after a faction caps all 5; the capping faction gets Blessing of Auchindoun, but NWB doesn't track the buff. `terokFaction` is the controlling side: 1 neutral, 2 Alliance, 3 Horde.

### 3.2 Detection (Data.lua:3822-3889 events, `getTerokkarData` 3924-4157)

**Events:**
- `UPDATE_UI_WIDGET` with `widgetID == 3097` triggers a read, but only when all of these hold:
  - more than 600 s since the last group join
  - more than 60 s since `ZONE_CHANGED_NEW_AREA`
  - more than 120 s since `PLAYER_ENTERING_WORLD`
- `PLAYER_ENTERING_WORLD` into 1952, or `AREA_POIS_UPDATED` on entering 1952, clears `lastTerokNPCID`. You must then target or mouse over **any** creature in 1952 before recording; that sets `lastTerokNPCID` at NWB.lua:7886-7889.

**Widgets:** `C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo`:

| Widget | Meaning |
|---|---|
| 3097 | neutral |
| 3118 | Alliance-controlled |
| 3119 | Horde-controlled |
| 3111 / 3112 | capture-progress pair |

- All of 3097, 3118 and 3119 must exist, and `UIWidgetTopCenterContainerFrame` must be shown with a shown child.
- **Capture stage** (3111 and 3112 both have `state == 1`): wipe `terokTowers`, `terokTowersTime` and `terokFaction` on the current layer, then return.
- Otherwise: `controlType` = 1, 2 or 3 for whichever of 3097, 3118 or 3119 has `state == 1` **and** is the shown child's `widgetID`.

**Parsing:** match `(%d+):%s*(%d+)` in that widget's `.text`, as hours and minutes.
- Fallback: collect all `%d+` and require exactly 2 numbers.
- Bug: the neutral fallback reads `alliance.text`.
- `timestamp = now + h*3600 + m*60`, which must be > 0 and under 22000 s away.

**Layer:**
- `lastKnownLayerMapID` (from §2.6, via the Terokkar zoneUID's layerMap), else `lastKnownLayerMapIDBackup`.
- The layer must exist locally.

**Write rules** (layered):
- Accept only if `timestamp - old > -1800`.
- `validateTerokkarRecord`: reject if another layer has a `terokTowers` within ±30 s.
- Debounce: wait 2 s, then use the latest reading. The widget sometimes fires about 565 s behind (Data.lua:4106-4113).
- `terokCache`: the **first** reading only primes the cache. A later reading more than 100 s away from the cache is treated as a forced layer change: wipe the layer knowledge and `lastTerokNPCID`. Otherwise set:
  - `terokTowers = ts`, `terokTowersTime = now(reading)`, `terokFaction = controlType`
  - `terokTowers10 = true` if more than 900 s remain
- **Send:** YELL plus GUILD with `type = "terokkar"`, only if all of these hold:
  - the old value was still in the future
  - this isn't the first reading since load
  - the new value is under 21500 s away
  - at least 175 s since the last terok send
- Moving from Terokkar to Shattrath (`AREA_POIS_UPDATED`, not on a taxi) yells terok data after 14 s, if still in 1955 and at least 120 s since the last such send (Data.lua:3875-3887).

### 3.3 Display time and drift correction

`getTerokEndTime(towers, towersTime)` (NWB.lua:2762-2779):
- `end = towers + floor(((towers - towersTime) / 60) * 2.7507)`
- The widget clock runs about 2.75 s slow per real minute.
- **Always display `end`, not `terokTowers`.**

### 3.4 Warnings (ticker, NWB.lua:1088-1124)

- When `terokTowers10` is set and `end - now` is in [570, 600]: clear the flag and emit `"Terokkar Forest towers reset in 10 minutes (Layer N)."`.
- Targets:
  - chat if `terokkarChat10` (default false)
  - middle screen if `terokkarMiddle10` (default false)
  - guild if `guildTerok10` (default **0**), via the election with prefix `"[NWB] "`
- This is the only guild post NWB makes on TBC (NWB.lua:1478-1480).
- At `end < now` the layer's terok fields are deleted.
- The display keeps an expired timer for 3599 s as `-MM:SS (expired)` in red (`showExpiredTimersTerok` default true).

### 3.5 Display

**Minimap tooltip, per layer** (NWB.lua:4477-4526):
- Tower icon by faction:
  - `alliancetower.blp` (2)
  - `hordetower.blp` (3)
  - `neutraltower.blp` (otherwise)
- Text: `"Terokkar: 2 hours 5 minutes."` plus `" (<time>)"` if `showTimeStamp`, or `"Terokkar: No current timer."`.

**World-map pin:**
- Default position: 94, 82 on Terokkar (1952).
- When you view the Shattrath map with `showShatWorldmapMarkersTerok`: 93, 79 on 1955.
- One pin per layer, with a `[Layer N] (zoneUID)` label (Data.lua:4202-4204, 4641-4656, 4211-4230).

### 3.6 Storage and sync keys

Per layer: `terokTowers` (L), `terokTowersTime` (U), `terokFaction` (M). Receive validation is in §7.4.

### 3.7 Hellfire

- `hellfireRep = now` is stored per layer on the Hellfire Citadel yell:
  - Horde: Nazgrel, "Hellfire Citadel is ours"
  - Alliance: Force Commander Danath Trollbane, "The feast of corruption is no more"
  - (WorldBuffs.lua:466-484)
- It is **not sent**: the send is commented out (Data.lua:1088-1098). It is not displayed.
- It is shortKey `N` and in `validKeys`, so it could arrive from older senders. Ignore it.
- **[UNC]** The meaning is probably the "Hellfire rep event".

---

## 4. Daily quests (TBC)

### 4.1 Detection (Data.lua:5468-5536)

The frame is inactive on Classic. Events used: `GOSSIP_SHOW`, `QUEST_FINISHED` and `QUEST_ACCEPTED`. There is no quest-log scan and no gossip-text parse.

1. `GOSSIP_SHOW`: remember the npcID of `UnitGUID("npc")`.
2. `QUEST_FINISHED` with that npcID ∈ {24370, 24369, 15350, 15351, 20735, 31439}: set `lastGossipClosed = GetTime()`.
3. `QUEST_ACCEPTED`: read `local _, questID = ...`, so the code expects the 2-argument `(questLogIndex, questID)` form. **[UNC]** whether 2.5.6 passes one or two arguments; a clean implementation should take the last numeric argument.
   - The quest is accepted only if `GetTime() - lastGossipClosed < 2`. That restricts it to accepted from the NPC, not shared.
   - **Normal dungeon daily**: NPC 24370 Nether-Stalker Mah'duun (31439 is Wrath's Archmage Timear). Quest in `dungeonDailies` → `tbcDD = id`, `tbcDDT = now`.
   - **Heroic daily**: NPC 24369 Wind Trader Zhareem (20735 is Wrath). Quest in `heroicDailies` → `tbcHD` / `tbcHDT`.
   - **PvP daily**: NPC 15350 Horde Warbringer or 15351 Alliance Brigadier General. Quest in `pvpDailies` → `tbcPD` / `tbcPDT`.
   - Each detection then sends YELL plus GUILD data. Dungeon and heroic use type `"heroicDailies"`; PvP uses `"pvpDailies"`.
   - No cooking or fishing dailies are tracked.

### 4.2 ID tables ([TBC] branch, Data.lua:4931-5236)

The value sent is the small **id**, not the questID.

**Dungeon (Mah'duun), questID → id, dungeon (abbreviation):**

| questID | id | Dungeon |
|---|---|---|
| 11389 | 1 | Arcatraz (Arc) |
| 11371 | 2 | Steamvault (SV) |
| 11376 | 3 | Shadow Labyrinth (SLabs) |
| 11383 | 4 | Black Morass (BM) |
| 11364 | 5 | Shattered Halls (ShatH) |
| 11500 | 6 | Magisters' Terrace (MGT) |
| 11385 | 7 | Botanica (Bot) |
| 11387 | 8 | Mechanar (Mech) |

**Heroic (Zhareem), questID → id, dungeon (abbreviation):**

| questID | id | Dungeon |
|---|---|---|
| 11369 | 1 | Underbog (Bog) |
| 11384 | 2 | Botanica (Bot) |
| 11382 | 3 | Black Morass (BM) |
| 11363 | 4 | Shattered Halls (ShatH) |
| 11362 | 5 | Blood Furnace (BF) |
| 11375 | 6 | Shadow Labyrinth (SLabs) |
| 11354 | 7 | Ramparts (Ramps) |
| 11386 | 8 | Mechanar (Mech) |
| 11373 | 9 | Mana-Tombs (MT) |
| 11378 | 10 | Old Hillsbrad (OHB) |
| 11374 | 11 | Auchenai Crypts (AC) |
| 11372 | 12 | Sethekk Halls (Sethekk) |
| 11368 | 13 | Slave Pens (SP) |
| 11388 | 14 | Arcatraz (Arc) |
| 11370 | 15 | Steamvault (SV) |
| 11499 | 16 | Magisters' Terrace (MGT) |

Quest names are the English "Wanted: …" titles. They are localized at runtime via `C_QuestLog.GetQuestInfo(questID)` (Data.lua:5276-5294).

**PvP ("Call to Arms: X"), questID → id:**

| Battleground | Horde questID → id | Alliance questID → id |
|---|---|---|
| Warsong Gulch | 11342 → 1 | 11338 → 5 |
| Arathi Basin | 11339 → 2 | 11335 → 6 |
| Alterac Valley | 11340 → 3 | 11336 → 7 |
| Eye of the Storm | 11341 → 4 | 11337 → 8 |
| Strand of the Ancients | 13407 → 9 | 13405 → 11 |
| Isle of Conquest | 14164 → 10 | 14163 → 12 |

### 4.3 Reset and validity

- There is **no reset-time computation**. A daily counts as valid while `now - tbcXDT < 86400` (Data.lua:1207-1226 for send; NWB.lua:4956-5003 for display).
- `GetQuestResetTime` is not used for dailies.

### 4.4 Storage and sync

- Top level of `NWB.data`: `tbcDD/tbcDDT` (Q/R), `tbcHD/tbcHDT` (O/P), `tbcPD/tbcPDT` (S/T).
- Each pair is sent only if the id is > 0 and was seen less than 86400 s ago.
- **Receive** (top-level loop, Data.lua:1976-2033). A pair is processed when its `…T` key passes all of:
  - generic gate: `v ~= 0`, `v > local tbcXDT` (local defaults to 0), `validateTimestamp` (≤ now+30000 and ≤ 2585912598)
  - level > 5 and the anti-forgery token
  - companion id is numeric, > 0 and found in the id table (`getHeroicDailyData` etc.)
- On success it overwrites both id and time. `dailyDataUpdated` triggers a cache refresh.
- There is no lower age bound on receive; display filters out anything older than 24 h.

### 4.5 Display

**Minimap tooltip** (NWB.lua:4956-5003):
- `"Daily (N) <name> (<abbrev>)"`, `"Daily (H) …"` and `"Daily (<faction icon>) <name>"`, or `"… Unknown."`.
- Followed by "Completed PvP dailies:" with Hellfire Towers, Terokkar Towers and Nagrand Halaa, checked via `C_QuestLog.IsQuestFlaggedCompleted`:
  - Horde: 10110, 11506, 11503
  - Alliance: 10106, 11505, 11502

**Shattrath world-map pins** (`showShatWorldmapMarkers`): normal daily at 65, 92 and heroic at 65, 95 on 1955 (Data.lua:5753-5756).

**Globals:** `NWB_DailyNormal`, `NWB_DailyHeroic` and `NWB_DailyPvp` are exported for WeakAuras.

---

## 5. Classic world buffs (what still runs on TBC)

### 5.1 NPCs, yells and delays

All matching is `string.match(msg, L[...])` on `CHAT_MSG_MONSTER_YELL` / `CHAT_MSG_MONSTER_SAY`, with a name match on `L[npcName]` (WorldBuffs.lua:308-490). NPC IDs come from CLEU buff sources and UNIT_DIED.

**Rend (Warchief's Blessing)**
- NPC: Thrall (4949, Org) or Herald of Thrall (10719, Barrens).
- 1st yell substring: "Rend Blackhand, has fallen".
- 2nd yell substring: `L["Be bathed in my power"]` = "Battle for the glory of the Horde".
- Drop announced as "Rend will drop in **6** seconds." Crossroads is prefixed "(Crossroads)".

**Onyxia (Rallying Cry of the Dragonslayer)**
- NPC: Horde Overlord Runthak (14392), Alliance Major Mattingly (14394). The buff source is the hidden NPC 173758 (Horde) / 173754 (Alliance).
- Horde yells: 1st "Onyxia, has been slain", 2nd "Be lifted by the rallying cry".
- Alliance yells: 1st "history has been made", 2nd "Onyxia, hangs from the arches".
- Drop delay: **14** s.

**Nefarian (Rallying Cry of the Dragonslayer)**
- NPC: Horde High Overlord Saurfang (14720), Alliance Field Marshal Afrasiabi (14721) or Field Marshal Stonebridge. The buff source is the same hidden NPCs.
- Horde yells: 1st "NEFARIAN IS SLAIN", 2nd "Revel in his rallying cry".
- Alliance yells: 1st "the Lord of Blackrock is slain", 2nd "Revel in the rallying cry".
- Drop delay: Horde **14** s, Alliance **12** s. Comments say about 15.

**Zandalar (Spirit of Zandalar)**
- NPC: Molthor (Yojamba Isle; any SAY counts) or Zandalarian Emissary (Booty Bay).
- 1st yell substring: "Begin the ritual" or "The Blood God". A text containing "Temple of Atal'Hakkar" is ignored.
- 2nd yell substring: "slayer of Hakkar".
- Drop delay: "30 seconds", or "50" for an Emissary yell or a Molthor SAY.

Additional yell rules:
- `skipStringCheck` (match on NPC name only) applies for these locales:
  - Horde: ptBR, esES, esMX, itIT
  - Alliance: the same plus zhCN
  - Always: Field Marshal Stonebridge
- Only NPC names and the yell substrings are localized (`L[...]` in each `Locale/*.lua`). The output messages are localized too (rendFirstYellMsg etc.).

**Yell timestamps:**
- 1st yells set `NWB.data.<type>Yell = now`; 2nd yells set `<type>Yell2`.
- A first-yell notice runs `doFirstYell`: a 40 s per-type cooldown (60 s for zan), a flash, a sound, the middle-screen text and a BigWigs bar.
- It is also forwarded as `"yell <ver> <lvl> <K> <type>[ <layerNum>[ <arg>]]"` to GUILD (and RAID or PARTY for zan) (WorldBuffs.lua:1623-1775).

### 5.2 Buff-drop timer

CLEU `SPELL_AURA_APPLIED` or `SPELL_AURA_REFRESH` on the player (WorldBuffs.lua:767-912).

**Spell IDs:**
- Rend: 16609 or 355366
- Ony/Nef: 22888 or 355363
- Zan: 24425 or 355365

**Conditions:**
- remaining duration ≥ max − 0.5 − `buffLag` (15)
- the source is a Creature with the right npcID (above)
- `now - Yell2 < 30` or `now - Yell < 30`; Nef is checked first, then Ony only if `now - nefYell2 > 30`

**Timer value:** the timer = **the time the buff landed** (`GetServerTime()`), **not** yell time + delay. A received timer must have its Yell within ±120 s.

**Where it is set:**
- `setRendBuff`: Horde in 1454 or 1413; Alliance in 1453, 1413 or 1454.
- `setOnyBuff` and `setNefBuff`: Horde 1454 or 1413; Alliance 1453 or 1413. They share a 20 s lockout with each other.
- Layer = `mapLayerToParent(sourceGUID zoneUID)`, i.e. the Org/SW zoneUID looked up in the layerMaps. The layer must already exist; creation from a buff is Classic-only (WorldBuffs.lua:1329-1340, 1456-1470).

**Cooldowns:** reset = timer + 10800 (rend), 21600 (ony) or 28800 (nef).

**Warnings** (ticker, NWB.lua:1061-1086; `doWarning` 1337-1450):
- At 30, 15, 10, 5 and 1 min, and at 0 ("A new %s buff can be dropped now").
- Text: `"%s resets in %s"` + " (Layer N)" + ".".
- Rend warnings only fire if there are fewer than 2 layers (WorldBuffs.lua:191-200).
- Suppressed when `NpcDied > Timer`.
- **[TBC]** Chat and middle-screen warnings can still print. Guild posts never happen (see §5.4).

### 5.3 NPC killed and NPC walking

**NPC killed:**
- CLEU `UNIT_DIED` with destName Runthak or Saurfang (Horde, in zone 1454 or 1411), or Mattingly, Afrasiabi, Stonebridge or npc 14721 (Alliance, in 1453 or 1429).
- Sets `layers[parent].onyNpcDied` / `nefNpcDied = now`.
- Message: "Overlord Runthak has just been killed (Onyxia buff NPC)." and the equivalents.
- Sent as `"npcKilled … <ony|nef>[ <layerNum>]"` to GUILD, then data to GUILD and YELL (WorldBuffs.lua:647-745).
- The NPC respawns after 360 s (NWB.lua:507). The "respawn" message fires at 360 s.

**NPC walking** (Horde only):
- Triggered on `GOSSIP_CLOSED` from 14392 or 14720 in Org, inside the box x 0.5013-0.5250, y 0.7389-0.7662.
- The close must not have come from the close button, the player must not be moving, and the NPC must not be stationary-targeted or in combat.
- Effect: "Onyxia NPC has started walking!" / "Nefarian NPC has started walking!", and `"npcWalking … <type>[ <layer>]"` to GUILD (NWB.lua:9737-9813, 9917-9946).

**Hand-in:** `QUEST_TURNED_IN` of 4974, 7491, 7496, 7784, 7782 or 8183 → `"handIn … <questID>"` on YELL. Receivers print "<Buff> quest handed in by <name>." if `handInMsg` is set (default false) (NWB.lua:1943-1949; WorldBuffs.lua:1906-1968).

### 5.4 Guild "one sender" election and `!wb`

`sendGuildMsg` (NWB.lua:1462-1578):
1. Collect online, non-mobile guild members who are in `hasAddon`.
2. If `msgType` is given, keep only members whose stored settings have it = 1/true and `a` ≠ 1, plus yourself if your own option is on. A `minVersion` filter is optional.
3. The alphabetically first full name `"Name-Realm"` posts `"[WorldBuffs] " .. msg`, or the given prefix.

**`!wb` and `!dmf`:**
- A guild line starting with `!wb` (5 s cooldown) runs `getShortBuffTimers`.
- Format: `"(Rend: 1 hour 5 minutes) (Onyxia: No timer [L1]) (Nefarian: 3 hours 2 minutes [L2])"`. Without a layer argument it uses the shortest timer per buff across layers, tagged `[L<n>]`.
- `!dmf` replies with the DMF time string.

**[TBC]** `sendGuildMsg` returns unless `msgType` is `guildTerok10` or `guildWintergrasp10` (NWB.lua:1478). So on TBC there are **no** `!wb`, buff-dropped, first-yell, NPC-killed, walking or songflower guild posts. Only the Terokkar 10-minute post exists.

### 5.5 [TBC] world-buff display

- Rend, Ony and Nef timers are **hidden** in the minimap tooltip; they show only when `expansionNum < 2` or prepatch (NWB.lua:4391).
- `/wb` on layered realms prints only "You are on a layered realm." and "Click here to view current timers." (NWB.lua:589-592).
- The data is still recorded and synced per layer. **[UNC]** Whether TBC Anniversary drops of these buffs happen at all; low priority.

---

## 6. Songflowers (Felwood, uiMap 1448)

### 6.1 Spots (Felwood.lua:13-34), x%, y%

| Key | x | y | Subzone (localized) |
|---|---|---|---|
| flower1 | 63.9 | 6.1 | North Felpaw Village |
| flower2 | 55.8 | 10.4 | West Felpaw Village |
| flower3 | 50.6 | 13.9 | North of Irontree Woods |
| flower4 | 63.3 | 22.6 | Talonbranch Glade |
| flower5 | 40.1 | 44.4 | Shatter Scar Vale |
| flower6 | 34.3 | 52.2 | Bloodvenom Post (Horde enUS adds " FP") |
| flower7 | 40.1 | 56.5 | East of Jaedenar |
| flower8 | 48.3 | 75.7 | North of Emerald Sanctuary |
| flower9 | 45.9 | 85.2 | West of Emerald Sanctuary |
| flower10 | 52.9 | 87.8 | South of Emerald Sanctuary |

### 6.2 Respawn and detection

**Respawn:** 1500 s (25 min) after pick.

**Pick detection** (Felwood.lua:139-180, 346-470):
- CLEU `SPELL_AURA_APPLIED` or `SPELL_AURA_REFRESH` with `spellName == L["Songflower Serenade"]` (spell 15366), while in 1448.
- **Self:** buff remaining ≥ 3599 s.
- **Other player:** allowed unless `mySongflowerOnly`. All of these must hold:
  - not hostile in a contested zone
  - not seen with the buff before
  - "detected" (seen via any CLEU event, target or mouseover) between 1 s and 600 s ago
  - not unbooned in the last second
  - the flower has no timer less than 1440 s old
- Flower = the first whose Euclidean distance in map-percent coordinates `(x*100, y*100)` is ≤ 1.5.
- Picks are de-duplicated within 5 s.

**Storage [TBC]:**
- `layeredSongflowers = true` on any layered realm (Felwood.lua:332-340), so the timer is stored as `layers[L].flowerN = now`.
- `L` is resolved in this order:
  1. `lastKnownLayerMapID` (only if there are ≥ 2 layers)
  2. `lastKnownLayerMapIDBackup` (Felwood-at-logon fallback, within 120 s of login)
  3. the single layer, if exactly 1 exists
- Otherwise the timer is stored top-level only, and NWB prints `L["flowerWarning"]`.
- Felwood is **not** in the TBC whitelist, so (1) works only if the layer is still known from elsewhere. **[UNC]** whether that holds in practice.
- The top-level `flowerN` is also set but **not sent** on layered realms.

**Sharing:** `sendData` to GUILD and YELL (layer field `fN`), plus `"flower <ver> <lvl> <K> flowerN[ <layerNum>]"` to GUILD if `guildSongflower` is set (default 0).
- Receive rule: don't overwrite a layered flower that is less than 1500 s old (Data.lua:1785-1788).
- Close-timestamp check: ±10 s.

**Display:**
- World map (1448): icon `spell_holy_mindvision`, one timer box per layer `[L<n>] MM:SS` (Felwood.lua:573-750).
- A minimap marker.
- `/sf` lists "Songflower: (Subzone 12m30s) …" for the current layer.
- Guild text "Songflower picked at %s, next spawn in 25mins." is never posted on TBC.

### 6.3 Tubers and dragons

- Whipper Root Tuber: item 11951, `tuber1..6`. Night Dragon's Breath: item 11952, `dragon1..4`.
- Detected via `CHAT_MSG_LOOT` in 1448 within range of a spot (Felwood.lua:36-55, 214-276).
- Timers are local only on TBC: they are sent only when `isSOD` (Data.lua:1186-1194). Ignore them.

---

## 7. Decoding NWB `data` for these features

### 7.1 Envelope

`"data <ver> <lvl>[-<layerOrdinal>] <K> " .. LibSerialize(shortTable)` (see Part 2 §3).
- After `Deserialize`, run `convertKeys(t, false)`: recursively replace each key found in `shortKeys`; numbers and unknown keys stay as-is (Data.lua:2419-2459).
- `NWB:config` then zeroes duplicate values, per table (Part 2 §3.2).

### 7.2 Short-key entries needed (short → long; reverse for sending)

| Short | Long | Short | Long |
|---|---|---|---|
| n | rendTimer | o | rendYell |
| s | onyTimer | t | onyYell |
| y | nefTimer | z | nefYell |
| x | onyNpcDied | D | nefNpcDied |
| E | lastSeenNPC | af | spawn |
| L | terokTowers | U | terokTowersTime |
| M | terokFaction | N | hellfireRep |
| O | tbcHD | P | tbcHDT |
| Q | tbcDD | R | tbcDDT |
| S | tbcPD | T | tbcPDT |
| f1..f10 | flower1..flower10 | ae | npcID |

- Literal (not shortened): `layers`, `layerMap`, `created`, `GUID`, and the settings owner key `"Name-NormalizedRealm"`.
- Settings sub-keys (inside the `"Name-Realm"` table): a, b, c, d, e, f, g, j, l, K, V (Part 2 §4.1).
- **Key collisions to be careful of:**
  - Single letters mean different things at different depths, but the mapping is global: `l` is always guild1, `f` is always guildSongflower. Inside layer tables only the timer letters appear.
  - Expand **before** interpreting. Unknown keys (e.g. `p`, `u`, `A` = yell2) may appear from other flavours; ignore them.

### 7.3 Where the fields live (TBC sender, `createDataLayered` Data.lua:922-1269)

**Top level:**
- `layers` = `{ [zoneUID:int] = layerTable }`
- `tbcDD/DDT`, `tbcHD/HDT`, `tbcPD/PDT` (ints)
- GUILD only: `["Name-Realm"] = {a=0|1, …}`. A value may be a **boolean** if the user's saved option is true/false.
- **Not present on TBC:** top-level world-buff timers, top-level `flowerN`, `timerLog`, wintergrasp.

**`layerTable`** (each field only when relevant):
- `n`/`o`: only when the rend timer is less than 10800 s old.
- `s`/`t`: when the ony timer is less than 21600 s old.
- `y`/`z`: when the nef timer is less than 28800 s old.
- `x` (onyNpcDied): when it is newer than onyTimer and within the cooldown.
- `D` (nefNpcDied): same condition, **Alliance senders only**.
- `fN`: when less than 1500 s old.
- `L`/`U`/`M`: when `terokFaction` is set and `now < L < now + 21500`.
- `E` (lastSeenNPC): when less than 7200 s old.
- `af` (spawn): when > 0 and the layer table exists.
- `layerMap = { [zoneUID:int] = uiMapID:int }`:
  - Included per layer on the first send of the session, then every 3600 s, or every 1840 s per channel when a timer is present.
  - Never sent to PARTY or RAID by the global gate; omitted for type wintergrasp; only if it has fewer than 70 entries.
  - It may also contain a **string key `"created"`** with an epoch value (NWB.lua:8178, not always stripped). Skip non-number keys.

**Typed sends** (`type` arg):
- `"terokkar"`: only layers with terok, plus E, af and layerMap.
- `"heroicDailies"`: DD and HD, plus every layer's E, af and layerMap.
- `"pvpDailies"`: PD, plus layers.

### 7.4 Receive validation to mirror (Data.lua:1544-2094)

**Gates:**
- The level gate (`lvl > 5`, Classic or GUILD exempt for layers) and the anti-forgery token apply. A listener can't check the token; treat everything as untrusted.
- Per message: `rendTimer`, `onyTimer` and `nefTimer` need a numeric matching Yell within ±120 s, else drop that buff's fields (`validateData` 2199-2214, 1563-1594).

**Per layer:**
- The zoneUID key must be a number, else drop the whole message.
- Skip the layer if any of:
  - `lastSeenNPC` is missing or `now - E > 7200`
  - all timers are 0
  - the layer is locally disabled
- An unknown layer is created up to 20 layers.
- Within a layer, drop a buff timer equal to another layer's same timer, or older than its cooldown.

**Numeric merge:**
- Newest wins (`v > local`, `v ~= 0`).
- `validateTimestamp`: ≤ now + 30000 and ≤ 2585912598.
- `validateCloseTimestamps`: reject if within ±30 s (±10 s for flowers and `hellfireRep`) of the same key on **any** layer, including the target layer. It is skipped for `rendTimer`, `terokTowers` and `terokFaction` because `sharedLayerBuffs` is true, and skipped for `spawn`.
- `lastSeenNPC` only increases; `spawn` only decreases (and only if ≠ 0); `created` is kept first.

**Terokkar:**
- Accept `L` if all of:
  - `U` > local `U`
  - `now < L < now + 21700`
  - `L > localL - 1800`
  - `|U - now| < 21700`
- If `L < localL - 300` it is only logged and not applied.
- On accept, set L, U and M together (Data.lua:1720-1756).

**layerMap:** add `zoneUID → mapID` only if all of:
- not present locally
- mapID is whitelisted
- the zoneUID isn't mapped in any layer
- the zoneUID isn't a layer key
- the layer doesn't already map that mapID (Data.lua:1833-1855)

**Dailies:** see §4.4. **Flowers:** see §6.2.

### 7.5 LibSerialize types your decoder must handle

- **Strings:**
  - embedded (< 16 bytes): all keys and `"Name-Realm"`
  - `STR_8`: long realm names
  - `STRINGREF_8/16`: repeated keys longer than 2 chars, e.g. `"layerMap"` in each layer and settings names. Keys of 1-2 chars are never ref'd.
- **Numbers:**
  - embedded 7-bit (0-127): settings 0/1, terokFaction, daily ids
  - embedded 12-bit (128-4095): uiMapIDs such as 1944/1952, and small zoneUIDs
  - `NUM_16_POS` / `NUM_24_POS`: zoneUIDs ≥ 4096
  - `NUM_32_POS`: epochs (~1.79e9)
  - Negative numbers do not normally occur.
  - Floats should not occur; every value is integral.
  - **[UNC]** Support `NUM_FLOAT` and `NUM_FLOATSTR` anyway (cheap); an old or buggy sender could emit e.g. a non-integral terokTowers.
- **Booleans:** `BOOL_T` / `BOOL_F` (settings).
- **Tables:**
  - `TABLE` (map) embedded, `TABLE_8` or `TABLE_16`, nested 3-4 deep: top → layers → layer → layerMap.
  - `ARRAY` and `MIXED` are only possible if keys happen to be 1..n. That is unlikely (zoneUIDs), but implement them.
  - `TABLEREF`: not expected; implement it for safety.
- The outer string S is itself a LibSerialize **string** object, typically `STR_8` or `STR_16`.

### 7.6 Worked examples (before LibSerialize, after shortening)

**A. YELL from a Horde TBC user who just re-read the Terokkar widget** (type "terokkar"):
```lua
{ layers = { [11872] = { L = 1792014600, U = 1792003020, M = 3,
                         E = 1792002911, af = 1791950112,
                         layerMap = { [11873] = 1952, [11879] = 1944 } } } }
```
- This is serialized, and then S = `"data 3.42 70 <K> "..ser` is serialized, deflated and chat-encoded.
- Expanded: `terokTowers` = 1792014600 (raw), `terokTowersTime` = 1792003020.
- Display end = 1792014600 + floor((11580 / 60) * 2.7507) = 1792014600 + 530 = **1792015130**, Horde-controlled, on the layer whose Shattrath zoneUID is 11872.

**B. GUILD after accepting the heroic daily** (type "heroicDailies"):
```lua
{ layers = { [11872] = { E = 1792002911, af = 1791950112 },
             [11890] = { E = 1792001777, af = 1791949000 } },
  O = 7, P = 1792004000,          -- heroic id 7 = Hellfire Ramparts (Nazan's Riding Crop)
  Q = 3, R = 1791990000,          -- normal id 3 = Shadow Labyrinth
  ["Watcher-Spineshatter"] = { a = 0, b = 1, c = 1, d = 1, e = 1, f = 0, g = 1, j = 1, l = 1, K = 1, V = 0 } }
```
- The level field is `"70-1"` (guildL).
- Note that `E` values differ between layers. The `config` filter would zero identical values.

---

## 8. Other user-visible TBC behaviour (brief)

**Minimap button tooltip** (`updateMinimapButton`, NWB.lua:4341-5040), in order:
1. "Nova World Buffs".
2. Per layer: `[Layer N]  (zone <zoneUID>) (Active 2d3h)`, then that layer's "Terokkar: …" line.
3. A top-level Terokkar line, only if non-layered data exists.
4. A separator.
5. The three "Daily (N/H/PvP)" lines.
6. "Completed PvP dailies:" with Hellfire Towers, Terokkar Towers and Nagrand Halaa.

There are no world-buff or DMF lines.

**Time formats:**
- Long: "1 hour 5 minutes", "2 hours", "3 minutes 4 seconds".
- Short: "1h5m".
- Medium: "1 hour 5 mins".
- Timestamps are 12 h "3:45pm" by default (`timeStampFormat = 12`, `timeStampZone = "local"`).

**Slash commands:**
- `/wb` prints the layered-realm notice and opens the layer/timers frame.
- `/wb guild` opens the guild layers list; `/wb layermap` shows the zone mappings; `/wb <n>` prints the short timers for layer n.
- `/dmf`, `/sf` and `/buffs` (buff tracker per character, including the DMF cooldown) are as described above.
- `/layer` also exists.

**Chat and other notices:**
- Messages are prefixed `[NWB]`, `[WorldBuffs]` or `[DMF]` and clickable.
- First-yell, NPC-killed and walking notices received from guild members still show locally (middle screen, flash, sound), but are never posted to guild chat on TBC.

**Periodic sends:** a full YELL every 1200 s, plus taxi and logon yells (Part 2 §2). This is the main way a listener hears non-guild layers and Terokkar data.

