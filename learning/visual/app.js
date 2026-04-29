const flowData = {
  boot: {
    label: "Local Boot",
    title: "npm start は開発体験を1本化する。",
    body:
      "zlib shim、schema generation、frontend bundle、backend server をまとめて立ち上げる。Google Client ID がなければ質問し、dev login のみでも動く。",
    tags: ["scripts/start-app.sh", "SQLite", "localhost:8080"]
  },
  auth: {
    label: "Auth Boundary",
    title: "Google と dev login は同じ user/session モデルへ合流する。",
    body:
      "Google tokeninfo の曖昧な wire shape は normalize してから claim validation する。dev lane は複数ユーザー検証を軽くし、本番では AUTH_DEV_MODE=0 で閉じる。",
    tags: ["Google Sign-In", "HttpOnly cookie", "fail closed"]
  },
  lesson: {
    label: "Lesson Runtime",
    title: "ブラウザ操作は UiAction → Msg → reducer へ流れる。",
    body:
      "View が data-action を出し、Runtime が UiAction として decode する。FRP layer は Event と Behavior で状態遷移と描画を接続する。",
    tags: ["App.UiAction", "App.Model.update", "ReactiveEnglish.Frp"]
  },
  vocab: {
    label: "Vocabulary Slice",
    title: "単語学習は lexeme + dimension ごとに進捗を持つ。",
    body:
      "Recognition、MeaningRecall、FormRecall、UseInContext、Collocation を分けて mastery と review event を保存する。word mission は lesson attempt とは独立した overlay。",
    tags: ["lexemes", "review spacing", "word mission"]
  },
  assure: {
    label: "ADD",
    title: "変更ごとに、最も効く保証レイヤーを選ぶ。",
    body:
      "型は配線、EBT は境界、PBT は広い入力空間、Lean は小さく安定した意味論に使う。全部を証明するのではなく、境界ごとに経済性を見る。",
    tags: ["TypeSystem", "EBT", "PBT", "Lean"]
  },
  release: {
    label: "GCP Release",
    title: "GitHub Actions は長期鍵なしで Cloud Run へ deploy する。",
    body:
      "workflow_dispatch で手動実行し、OIDC → Workload Identity Federation → deployer service account で認証する。DATABASE_URL は Secret Manager から注入する。",
    tags: ["OIDC", "Cloud Run", "Secret Manager"]
  }
};

const answers = {
  schema: {
    title: "A1. Schema bridge",
    body:
      "schema-bridge/src/SchemaBridge/Spec.hs を source of truth にして、Haskell と PureScript の Generated module を作る。これで API payload の shape ずれを型と生成で見える化する。"
  },
  add: {
    title: "A2. Typed boundary + EBT/PBT + proof",
    body:
      "wire shape は GoogleTokenInfo と normalize 関数で型付き境界にし、EBT で Bool/String の実例を叩き、PBT で reference model と比較し、Lean で受理条件の fail-closed 性質を証明する。"
  },
  deploy: {
    title: "A3. OIDC のため",
    body:
      "service account key は漏れた瞬間に長く使われる。GitHub OIDC + Workload Identity Federation なら、repo/branch 条件つきの短命認証で deployer service account を使える。"
  },
  frp: {
    title: "A4. 価値があるのは小さい temporal core",
    body:
      "この app で必要なのは UI/async event を reducer に流し、Behavior の更新で render と command dispatch を走らせること。高階 switching や連続時間まで広げると、学習アプリではなく FRP 研究になってしまう。"
  }
};

function setFlow(key) {
  const item = flowData[key];
  if (!item) return;

  document.querySelectorAll(".flow-button").forEach((button) => {
    button.classList.toggle("active", button.dataset.flow === key);
  });

  document.querySelector("#flow-label").textContent = item.label;
  document.querySelector("#flow-title").textContent = item.title;
  document.querySelector("#flow-body").textContent = item.body;
  document.querySelector("#flow-tags").innerHTML = item.tags
    .map((tag) => `<span>${tag}</span>`)
    .join("");
}

document.querySelectorAll(".flow-button").forEach((button) => {
  button.addEventListener("click", () => setFlow(button.dataset.flow));
});

document.querySelectorAll(".drill-card").forEach((card) => {
  card.addEventListener("click", () => {
    const answer = answers[card.dataset.answer];
    const panel = document.querySelector("#answer-panel");
    panel.innerHTML = `<h3>${answer.title}</h3><p>${answer.body}</p>`;
  });
});

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.12 }
);

document.querySelectorAll("[data-reveal]").forEach((element) => observer.observe(element));
