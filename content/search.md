---
title: "Search"
---

<link href="/pagefind/pagefind-ui.css" rel="stylesheet">
<div id="search"></div>
<script src="/pagefind/pagefind-ui.js"></script>
<script>
  window.addEventListener('DOMContentLoaded', function () {
    new PagefindUI({
      element: "#search",
      showSubResults: true,
      showImages: false
    });
  });
</script>

<style>
  .pagefind-ui {
    --pagefind-ui-primary: #32858b;
    --pagefind-ui-text: #eceae5;
    --pagefind-ui-background: #1a170f;
    --pagefind-ui-border: #32858b;
    --pagefind-ui-tag: #32858b;
    --pagefind-ui-border-width: 1px;
    --pagefind-ui-border-radius: 0;
    --pagefind-ui-font: "Fira Code", Monaco, Consolas, "Ubuntu Mono", monospace;
  }
</style>
