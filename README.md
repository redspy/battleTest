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
