# BattleTest

Godot 기반 포켓몬 싱글 대전 및 AI 연습 프로젝트입니다.

## 빌드

Node.js 의존성은 `npm ci`로 설치합니다. Godot 4.7.2와 대응하는 내보내기 템플릿이 필요합니다. Android 빌드에는 Godot 편집기에서 사용할 Android SDK와 JDK를 설정합니다.

이미지 저장소 접근 권한이 있는 환경에서 프로젝트 루트에 원본 GIF를 내려받습니다.

```sh
git clone https://github.com/redspy/battleTest_Image.git pokemon_gifs
```

`pokemon_gifs`에 원본 파일이 이미 있다면 기존 폴더를 그대로 사용합니다. 빌드 스크립트가 이미지 시트와 데이터 사본을 Godot 폴더에 생성합니다.

```sh
node scripts/build-app.mjs
node scripts/build-app.mjs --win
```

Godot을 자동으로 찾지 못하면 `GODOT` 환경 변수에 콘솔 실행 파일의 경로를 지정합니다. 결과물은 `build/BattleTest.apk`와 `build/windows/BattleTest.exe`에 생성됩니다.

## 커스텀 덱 추가 규칙

`다을`(`daeul`)을 커스텀 싱글 팀의 예시로 사용합니다.

- `data/pokemon/teams.json`의 `CUSTOM` 이벤트에 고유한 팀 ID로 등록합니다. 멤버는 서로 다른 6종이며, 대전에서는 3마리를 선출합니다. `summary`에 덱의 승리 조건, 기본 선출 순서, 상대에 따른 대체 선출을 적고 `roles`에는 포켓몬별 팀 내 역할을 적습니다.
- 각 멤버에 종·폼, 특성, 도구, 기술 4개, 성격과 훈련 포인트를 기록합니다. 레벨 50 실수치는 `Data.battle_stats`로 계산합니다. 포인트는 이 프로젝트의 66점 기준으로 배분하고 한 능력에 최대 32점을 줍니다. `boost`와 `reduce`는 성격과 일치시킵니다. 공식 도감과 대전 자료로 종족치·특성·습득 기술을 확인하고, 팀 설명에는 구성 의도를 적습니다.
- 신규 종·폼은 `data/pokemon/species.json`에 등록합니다. 신규 기술·도구·특성은 `data/pokemon/moves.json`에서 정의와 한글 표기를 확인합니다. 엔진에서 지원해야 하는 효과가 있으면 `godot/scripts/battle/engine.gd`에 구현하고, 동작을 자가 테스트로 확인합니다.
- 캐릭터 GIF는 해당 종과 폼이 일치하는 파일을 골라 `pokemon_gifs/<4자리 도감번호>_<이름>/<forms.file>.gif`에 둡니다. 나무위키에서 찾은 파일은 해당 폼의 `assetSource`에 문서 주소를, `assetUrl`에 GIF 직접 주소를 남깁니다. 원본 GIF 저장소와 게임 코드 저장소가 분리되어 있으므로 배포 시 새 원본 파일도 이미지 저장소에 반영합니다.
- `node scripts/build-sprites.mjs --set=pokemon`으로 데이터와 스프라이트 시트를 생성합니다. 이어서 `node scripts/build-app.mjs`로 자가 테스트와 Android 빌드를 실행합니다. 팀 상세와 AI 연습에서 3인 선출, 도구·특성·기술, 일반·변신 폼의 표시를 확인합니다. `godot/data`와 `godot/sprites`는 빌드 산출물입니다.
