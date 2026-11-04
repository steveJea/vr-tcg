// 정적 Tailwind 빌드 설정 (예전 cdn.tailwindcss.com 런타임과 같은 기본 설정)
// 다시 만들기: npx tailwindcss@3.4.17 -c tools/tailwind/tailwind.config.js -i tools/tailwind/input.css -o css/tw.css --minify
module.exports = {
  content: ['./*.html', './js/**/*.js', './data/**/*.{json,csv,js}'],
  theme: { extend: {} },
  plugins: [],
};
