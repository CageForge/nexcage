# Sprint 6.5 Plan: Legacy Refactoring and Modular Integration

Date: 2025-10-13
Owner: @moriarti
Status: Planned

Goals
- Перемістити `legacy/` до `archive/legacy/` без втрати історії
- Інтегрувати придатні елементи legacy у модульну архітектуру (`src/*` backends)
- Усунути імпорти на `legacy/*`, оновити шляхи
- Забезпечити успішну збірку та тести

Scope
- Каталог `legacy/` (усі підпапки: `bfc/`, `common/`, `config/`, `crun/`, `network/`, `oci/`, `performance/`, `proxmox/`, `raw/`, `zfs/`)
- Перевірка перетинів із `src/*` та `tests/*`

Deliverables
- `archive/legacy/` із повним вмістом
- Оновлені імпорти/посилання
- Будь-які виділені модулі перенесені в `src/*`
- `Roadmap/SPRINT_6.5_PROGRESS.md`, `Roadmap/SPRINT_6.5_COMPLETED.md`

Risks
- Зламані імпорти або символи після переміщення
- Дублювання реалізацій між `legacy/` та `src/`

Mitigations
- Масовий пошук посилань і поетапне оновлення
- Порівняння API, вибір єдиного джерела істини

Plan
1. Інвентаризація використань `legacy/` у коді
2. Переміщення `legacy/` → `archive/legacy/`
3. Оновлення імпортів/посилань
4. Витяг корисних модулів у `src/*` за потреби
5. Збірка, тести, виправлення
6. Документація і PR

Timebox
- Загалом: 1 робочий день
- Резерв: 2 години на виправлення збірки


