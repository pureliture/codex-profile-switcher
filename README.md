# Codex Profile Switcher

<!-- ──────────────── HERO BANNER ──────────────── -->
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:05070a,45:0f766e,100:3b82f6&height=230&section=header&text=Codex%20Profile%20Switcher&fontSize=50&fontColor=ffffff&animation=fadeIn&fontAlignY=36&desc=Local-first%20Codex%20Desktop%20profile%20switching&descSize=15&descAlignY=58" alt="banner" width="100%" />

<br/>

<img src="https://img.shields.io/badge/macOS-13%2B-111827?style=for-the-badge&logo=apple&logoColor=white" alt="macOS" />
<img src="https://img.shields.io/badge/SwiftPM-AppKit-f97316?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftPM AppKit" />
<img src="https://img.shields.io/badge/OAuth-only-22c55e?style=for-the-badge" alt="OAuth only" />
<img src="https://img.shields.io/badge/auth.json-only-3b82f6?style=for-the-badge" alt="auth only" />
<img src="https://img.shields.io/badge/codex--auth-not_used-ef4444?style=for-the-badge" alt="codex-auth not used" />

<br/><br/>

<h3>
  개인 계정과 엔터프라이즈 계정을 오가되,<br/>
  Codex sessions · history · MCP · skills · config는 그대로 공유하는 로컬 macOS 앱입니다.
</h3>

<br/>

<p>
  <a href="#-작동-구조"><img src="https://img.shields.io/badge/🏛️_Architecture-1e293b?style=for-the-badge" alt="Architecture" /></a>
  <a href="#-안전-경계"><img src="https://img.shields.io/badge/🛡️_Safety-1e293b?style=for-the-badge" alt="Safety" /></a>
  <a href="#-설치와-사용"><img src="https://img.shields.io/badge/🚀_Install-1e293b?style=for-the-badge" alt="Install" /></a>
  <a href="#-reference"><img src="https://img.shields.io/badge/📌_Reference-1e293b?style=for-the-badge" alt="Reference" /></a>
</p>

</div>

<br/>

<img src="https://capsule-render.vercel.app/api?type=rect&color=0:0f766e,100:3b82f6&height=3" width="100%" />

<br/>

## 🏛️ 작동 구조

> switch 대상은 `~/.codex/auth.json` 하나입니다. 나머지 Codex state는 그대로 둡니다.

<p align="center">
  <img src="assets/architecture.svg" alt="Codex Profile Switcher architecture" width="100%" />
</p>

<table>
<tr>
<td width="50%" valign="top">

### 🟦 Profile Snapshot

계정 추가는 isolated `CODEX_HOME`에서 official Codex login으로 진행합니다.
성공한 `auth.json`만 app-owned profile store에 저장합니다.

</td>
<td width="50%" valign="top">

### 🟩 Shared State Guard

switch 전후로 config, sessions, history, MCP, skills가 바뀌지 않았는지 확인합니다.
검증 실패 시 Codex restart 전에 rollback합니다.

</td>
</tr>
</table>

<br/>

<img src="https://capsule-render.vercel.app/api?type=rect&color=0:0f766e,100:3b82f6&height=3" width="100%" />

<br/>

## 🛡️ 안전 경계

<p align="center">
  <img src="assets/safety-flow.svg" alt="Safe auth switch flow" width="100%" />
</p>

<table>
<thead>
<tr>
<th align="center">허용</th>
<th align="center">차단</th>
<th align="center">복구</th>
</tr>
</thead>
<tbody>
<tr>
<td valign="top">

- `auth.json` snapshot 저장
- `~/.codex/auth.json` atomic replace
- Codex Desktop restart

</td>
<td valign="top">

- `codex-auth`
- API key mode
- usage/reset credit 조회
- config/session/MCP/skill 수정

</td>
<td valign="top">

- switch 전 active auth backup
- shared-state drift 감지
- 실패 시 backup restore

</td>
</tr>
</tbody>
</table>

<br/>

<img src="https://capsule-render.vercel.app/api?type=rect&color=0:0f766e,100:3b82f6&height=3" width="100%" />

<br/>

## 🖥️ 앱 화면

<p align="center">
  <img src="assets/panel-preview.svg" alt="Codex Profile Switcher window preview" width="72%" />
</p>

<br/>

<table>
<tr>
<td width="25%" valign="top">

### 1. Add Profile

개인/엔터프라이즈 계정을 각각 official login으로 추가합니다.

</td>
<td width="25%" valign="top">

### 2. Switch

원하는 profile을 선택하면 active `auth.json`만 교체합니다.

</td>
<td width="25%" valign="top">

### 3. Remove

inactive profile snapshot만 삭제합니다. active profile은 먼저 전환해야 합니다.

</td>
<td width="25%" valign="top">

### 4. Restart

검증이 끝난 뒤 Codex Desktop을 다시 열어 선택 계정을 반영합니다.

</td>
</tr>
</table>

<br/>

<img src="https://capsule-render.vercel.app/api?type=rect&color=0:0f766e,100:3b82f6&height=3" width="100%" />

<br/>

## 🚀 설치와 사용

```bash
git clone https://github.com/pureliture/codex-profile-switcher.git
cd codex-profile-switcher
bash scripts/install-app.sh
```

설치 위치:

```text
~/Applications/Codex Profile Switcher.app
```

`/Applications`에 설치하려면:

```bash
INSTALL_DIR=/Applications bash scripts/install-app.sh
```

필수 환경:

| 항목 | 필요 |
|---|---|
| macOS | 13+ |
| Xcode Command Line Tools | build/install |
| Codex Desktop | `/Applications/Codex.app` |

<br/>

## ✅ 검증 상태

| 항목 | 상태 |
|---|---|
| Core tests | 20 passed |
| `.app` bundle | build verified |
| Local install | `~/Applications` verified |
| Codesign | ad hoc seal valid |
| Live account switch | 각 팀원 Mac에서 계정별 1회 확인 필요 |

<br/>

## 📌 Reference

이 프로젝트는 [`lordydord/Codex-Account-Switcher`](https://github.com/lordydord/Codex-Account-Switcher)를 UI/UX reference로 참고했습니다.

다른 점은 명확합니다.

| 항목 | Codex-Account-Switcher | Codex Profile Switcher |
|---|---|---|
| 전환 방식 | `codex-auth` helper | app-owned `auth.json` snapshot |
| usage/reset | 있음 | 없음 |
| auto-switch | 있음 | 없음 |
| 수정 범위 | broader account tooling | `auth.json` only |
| 목표 | account switching utility | team-safe local profile switcher |

<br/>

## 🗂️ 데이터 위치

```text
~/.codex/auth.json
~/.codex-profile-switcher/registry.json
~/.codex-profile-switcher/profiles/<uuid>/auth.json
~/.codex-profile-switcher/backups/
```

`auth.json`과 token 값은 issue, screenshot, log에 올리지 마세요.

<br/>

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:3b82f6,50:0f766e,100:05070a&height=130&section=footer" width="100%" />

## License

MIT. See [LICENSE](./LICENSE).
