# Nexon API Used Endpoints

이 문서는 현재 프로젝트에서 실제로 사용할 Nexon OpenAPI 정보만 정리한다.

## 공통

### OCID 조회

- Endpoint: `/maplestory/v1/id`
- 사용 정보:
  - `ocid`: 캐릭터마다 부여된 고유 번호

## 캐릭터

### 캐릭터 목록 조회

- Endpoint: `/maplestory/v1/character/list`
- 사용 정보:
  - 계정
  - 캐릭터명
  - 월드
  - 직업
  - 레벨

### 캐릭터 기본 정보 조회

- Endpoint: `/maplestory/v1/character/basic`
- 사용 정보:
  - 캐릭터명
  - 월드
  - 직업
  - 레벨
  - 보유 경험치
  - 경험치 퍼센트
  - 길드
  - 사진/외형

### 능력치 조회

- Endpoint: `/maplestory/v1/character/stat`
- 사용 정보:
  - 캐릭터 능력치 정보

### 하이퍼스탯 조회

- Endpoint: `/maplestory/v1/character/hyper-stat`
- 사용 정보:
  - 프리셋별 하이퍼스탯
  - 현재 적용 중인 프리셋

### 어빌리티 조회

- Endpoint: `/maplestory/v1/character/ability`
- 사용 정보:
  - 프리셋별 어빌리티
  - 현재 적용 중인 프리셋

### 장착 장비 조회

- Endpoint: `/maplestory/v1/character/item-equipment`
- 범위:
  - 캐시 장비 제외
- 사용 정보:
  - 장비 프리셋
  - 아이템별 상세 정보

### 캐시 장비 조회

- Endpoint: `/maplestory/v1/character/cashitem-equipment`
- 사용 정보:
  - 캐시 장비 프리셋
  - 캐시 아이템별 상세 정보

### 장착 심볼 조회

- Endpoint: `/maplestory/v1/character/symbol-equipment`
- 사용 정보:
  - 심볼 이름
  - 아이콘
  - 심볼 레벨

### 적용 세트 효과 조회

- Endpoint: `/maplestory/v1/character/set-effect`
- 사용 정보:
  - 효과명
  - 세트 개수
  - 세트 레벨
  - 세트 효과

### 스킬 정보 조회

- Endpoint: `/maplestory/v1/character/skill`
- 사용 범위:
  - 하이퍼 스킬
  - 5차 스킬
  - 6차 스킬

### V매트릭스 조회

- Endpoint: `/maplestory/v1/character/vmatrix`
- 사용 정보:
  - 코어 이름
  - 코어 타입
  - 코어 레벨
  - 슬롯 인덱스

### HEXA 매트릭스 조회

- Endpoint: `/maplestory/v1/character/hexamatrix`
- 사용 정보:
  - 코어 이름
  - 코어 레벨
  - 이벤트 레벨
  - 코어 타입
  - 연결된 스킬

### HEXA 스탯 조회

- Endpoint: `/maplestory/v1/character/hexamatrix-stat`
- 사용 정보:
  - HEXA 스탯 정보

### 기타 능력치 영향 요소 조회

- Endpoint: `/maplestory/v1/character/other-stat`
- 사용 정보:
  - 제네시스 패스
  - 챌린저스 패스

### 장착 중인 시드링 조회

- Endpoint: `/maplestory/v1/character/ring-exchange-skill-equipment`
- 사용 정보:
  - 링 익스체인지 정보

### 예비 특수 반지 조회

- Endpoint: `/maplestory/v1/character/ring-reserve-skill-equipment`
- 사용 정보:
  - 링 이름
  - 반지 레벨
  - 아이콘
  - 설명

## 유니온

### 유니온 정보 조회

- Endpoint: `/maplestory/v1/user/union`
- 사용 정보:
  - 유니온 정보

### 유니온 아티팩트 조회

- Endpoint: `/maplestory/v1/user/union-artifact`
- 사용 정보:
  - 아티팩트 정보

### 유니온 챔피언 조회

- Endpoint: `/maplestory/v1/user/union-champion`
- 사용 정보:
  - 유니온 챔피언 정보

## 강화 이력

강화 이력은 공식 가격표와 조합해서 비용을 계산한다.
아이템 정보와 횟수 중심으로 저장한다.

### 스타포스 이력 조회

- Endpoint: `/maplestory/v1/history/starforce`
- 사용 정보:
  - 스타포스 강화 이력

### 잠재능력 재설정 이력 조회

- Endpoint: `/maplestory/v1/history/potential`
- 사용 정보:
  - 잠재능력 재설정 이력

### 큐브 이력 조회

- Endpoint: `/maplestory/v1/history/cube`
- 사용 정보:
  - 큐브 사용 이력

## 스케줄러

### 캐릭터 진행 상태 조회

- Endpoint: `/maplestory/v1/scheduler/character-state`
- 일일 사용 정보:
  - 콘텐츠명
  - 타입: `contents`, `quest`
  - 인게임 등록 여부
  - 현재 완료 횟수/점수
  - 최대 가능 횟수
  - 퀘스트 진행 상태
- 주간 사용 정보:
  - 콘텐츠명
  - 타입: `contents`, `quest`
  - 인게임 등록 여부
  - 현재 완료 횟수/점수
  - 최대 가능 횟수
  - 퀘스트 진행 상태
- 보스 사용 정보:
  - 보스명
  - 난이도
  - 초기화 주기
  - 리스트 순서
  - 등록 여부
  - 완료 여부
- 기타 사용 정보:
  - 주간 보스 처치 완료 횟수
  - 주간 보스 처치 제한 횟수
