const characters = [
  {
    id: "c1",
    name: "달빛나이트",
    job: "다크나이트",
    level: 275,
    image: "../design/claude-ui/uploads/i1934183597.png",
  },
  {
    id: "c2",
    name: "바람의그림자",
    job: "나이트로드",
    level: 261,
    image: "../design/claude-ui/uploads/i1934183597-33d04ca2.png",
  },
  {
    id: "c3",
    name: "새벽비숍",
    job: "비숍",
    level: 253,
    image: "../design/claude-ui/uploads/pasted-1783925212877-0.png",
  },
];

const events = [
  {
    title: "메이플스토리 여름맞이 출석 이벤트",
    date: "2026.06.24 ~ 2026.07.07",
    image: "../design/claude-ui/uploads/pasted-1783925212877-0.png",
  },
  {
    title: "뉴네임 옥션",
    date: "2026.06.25 ~ 2026.07.15",
    image: "../design/claude-ui/uploads/pasted-1783925723725-0.png",
  },
  {
    title: "챌린저스 월드 시즌4",
    date: "2026.06.18 ~ 2026.09.17",
    image: "../design/claude-ui/uploads/pasted-1783926870170-0.png",
  },
  {
    title: "하이퍼 버닝 MAX",
    date: "2026.06.18 ~ 2026.09.16",
    image: "../design/claude-ui/uploads/pasted-1783930979829-0.png",
  },
];

const notices = [
  { tag: "공지", title: "클린 캠페인 결과 발표", date: "2026.07.12" },
  { tag: "점검", title: "7월 정기 점검 안내", date: "2026.07.15" },
  { tag: "점검", title: "밸런스 패치 노트 v1.2.88", date: "2026.07.10" },
  { tag: "GM소식", title: "GM 이벤트 당첨자 발표", date: "2026.07.08" },
];

let selectedCharacterId = "c1";

const pages = {
  characters: "캐릭터 선택",
  scheduler: "스케줄러",
  events: "이벤트",
  notices: "공지사항",
  sunday: "이번주 선데이",
};

function selectedCharacter() {
  return characters.find((character) => character.id === selectedCharacterId) ?? characters[0];
}

function setPage(page) {
  document.querySelectorAll(".page").forEach((element) => element.classList.remove("active"));
  document.querySelector(`#page-${page}`).classList.add("active");

  document.querySelectorAll(".nav-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.page === page);
  });

  document.querySelector("#pageTitle").textContent = pages[page];
}

function renderActiveCharacter() {
  const character = selectedCharacter();
  document.querySelector("#activeCharacterName").textContent = character.name;
  document.querySelector("#activeCharacterInfo").textContent = `${character.job} · Lv.${character.level}`;
  document.querySelector("#alertCharacter").textContent = `${character.name} 님`;
}

function renderCharacters() {
  const grid = document.querySelector("#characterGrid");
  grid.innerHTML = "";

  characters
    .slice()
    .sort((a, b) => b.level - a.level)
    .forEach((character) => {
      const card = document.createElement("button");
      card.className = `character-card ${character.id === selectedCharacterId ? "selected" : ""}`;
      card.innerHTML = `
        <img src="${character.image}" alt="${character.name}">
        <div class="card-title-row">
          <strong>${character.name}</strong>
          ${character.id === selectedCharacterId ? '<span class="selected-badge">선택됨</span>' : ""}
        </div>
        <p>${character.job} · Lv.${character.level}</p>
      `;
      card.addEventListener("click", () => {
        selectedCharacterId = character.id;
        renderActiveCharacter();
        renderCharacters();
        setPage("scheduler");
      });
      grid.appendChild(card);
    });
}

function renderEvents() {
  const grid = document.querySelector("#eventGrid");
  grid.innerHTML = "";
  events.forEach((event) => {
    const card = document.createElement("article");
    card.className = "event-card";
    card.innerHTML = `
      <img src="${event.image}" alt="">
      <div>
        <strong>${event.title}</strong>
        <p>${event.date}</p>
      </div>
    `;
    grid.appendChild(card);
  });
}

function renderNotices() {
  const list = document.querySelector("#noticeList");
  list.innerHTML = "";
  notices.forEach((notice) => {
    const row = document.createElement("div");
    row.className = "notice-row";
    row.innerHTML = `
      <span class="notice-tag">${notice.tag}</span>
      <strong>${notice.title}</strong>
      <time>${notice.date}</time>
    `;
    list.appendChild(row);
  });
}

function showAlert() {
  document.querySelector("#floatingAlert").classList.add("visible");
}

function hideAlert() {
  document.querySelector("#floatingAlert").classList.remove("visible");
}

document.querySelectorAll("[data-page]").forEach((button) => {
  button.addEventListener("click", () => setPage(button.dataset.page));
});

document.querySelector("#previewAlertButton").addEventListener("click", showAlert);
document.querySelector("#dismissAlert").addEventListener("click", hideAlert);
document.querySelector("#goScheduler").addEventListener("click", () => {
  hideAlert();
  setPage("scheduler");
});

document.querySelector("#logoutButton").addEventListener("click", () => {
  document.querySelector("#logoutModal").classList.add("visible");
});

document.querySelector("#cancelLogout").addEventListener("click", () => {
  document.querySelector("#logoutModal").classList.remove("visible");
});

document.querySelector("#confirmLogout").addEventListener("click", () => {
  document.querySelector("#logoutModal").classList.remove("visible");
});

renderActiveCharacter();
renderCharacters();
renderEvents();
renderNotices();
showAlert();
