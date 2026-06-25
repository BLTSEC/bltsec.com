(() => {
  const targets = document.querySelectorAll('pre code.language-kusto, pre code.language-cql');
  if (!targets.length) return;

  const escapeHtml = (value) => value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

  const highlightCode = (raw) => {
    return raw.split('\n').map((line) => {
      const commentIndex = line.indexOf('//');
      const codePart = commentIndex >= 0 ? line.slice(0, commentIndex) : line;
      const commentPart = commentIndex >= 0 ? line.slice(commentIndex) : '';

      let html = escapeHtml(codePart);

      html = html.replace(/(&quot;.*?&quot;)/g, '<span class="tok-string">$1</span>');
      html = html.replace(/\b(ago|and|between|by|contains|count|dynamic|extend|fields|function|has|in|include|join|let|max|min|null|or|project|rename|search|sort|stats|summarize|table|values|where)\b/gi, '<span class="tok-keyword">$1</span>');
      html = html.replace(/\b(any|cidr|cidrmatch|collect|datetime_diff|dcount|groupBy|ipv4_is_in_any_range|make_set|tolower)\b(?=\()/g, '<span class="tok-function">$1</span>');
      html = html.replace(/\b(Timestamp|RemoteIP|RemoteIPType|RemotePort|Protocol|DeviceName|ProcName|ImageFileName|CommandLine|ComputerName|ContextProcessId|TargetProcessId|RemoteAddressIP4|InitiatingProcessFileName|InitiatingProcessCommandLine|InitiatingProcessFolderPath|InitiatingProcessParentFileName|InitiatingProcessIntegrityLevel)\b/g, '<span class="tok-field">$1</span>');
      html = html.replace(/\b\d+(?:\.\d+)?\b/g, '<span class="tok-number">$&</span>');
      html = html.replace(/(^|\s)(\||=~|!=|==|>=|<=|=)(?=\s|\w|&quot;|\()/g, '$1<span class="tok-operator">$2</span>');

      if (commentPart) {
        html += `<span class="tok-comment">${escapeHtml(commentPart)}</span>`;
      }

      return html;
    }).join('\n');
  };

  targets.forEach((block) => {
    block.innerHTML = highlightCode(block.textContent);
    block.dataset.highlighted = 'true';
  });
})();
