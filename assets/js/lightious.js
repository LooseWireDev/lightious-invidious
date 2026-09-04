(function () {
  "use strict";

  function playlistRequired(value) {
    return value === "playlist" || value.indexOf("playlist:") === 0 || value.indexOf("library_and_playlist:") === 0;
  }

  document.querySelectorAll("[data-selection-form]").forEach(function (form) {
    var checkboxes = Array.from(form.querySelectorAll('input[type="checkbox"]'));
    var count = form.querySelector("[data-selection-count]");
    var selectAll = form.querySelector("[data-select-all]");
    var rail = form.querySelector("[data-selection-rail]");
    var destination = form.querySelector("[data-destination-select], [data-bulk-action-select]");
    var playlistField = form.querySelector("[data-playlist-field]");
    var playlistSelect = playlistField && playlistField.querySelector("select");

    function updateCount() {
      var selected = checkboxes.filter(function (checkbox) { return checkbox.checked; }).length;
      if (count) count.textContent = selected + (selected === 1 ? " selected" : " selected");
      if (selectAll) selectAll.textContent = selected === checkboxes.length && checkboxes.length > 0 ? "Clear all" : "Select all";
      if (rail) rail.hidden = selected === 0;
    }

    function updatePlaylist() {
      if (!destination || !playlistField || !playlistSelect) return;
      var show = playlistRequired(destination.value);
      playlistField.hidden = !show;
      playlistSelect.disabled = !show;
      if (!show) playlistSelect.value = "";
    }

    checkboxes.forEach(function (checkbox) { checkbox.addEventListener("change", updateCount); });
    form.querySelectorAll("article[data-selectable-row], div[data-selectable-row]").forEach(function (row) {
      row.addEventListener("click", function (event) {
        if (event.target.closest("a, button, input, select, label")) return;
        var checkbox = row.querySelector('input[type="checkbox"]');
        if (!checkbox) return;
        checkbox.checked = !checkbox.checked;
        checkbox.dispatchEvent(new Event("change", { bubbles: true }));
      });
    });
    if (selectAll) {
      selectAll.addEventListener("click", function () {
        var shouldSelect = !checkboxes.every(function (checkbox) { return checkbox.checked; });
        checkboxes.forEach(function (checkbox) { checkbox.checked = shouldSelect; });
        updateCount();
      });
    }
    if (destination) destination.addEventListener("change", updatePlaylist);

    form.addEventListener("submit", function (event) {
      if (checkboxes.length > 0 && !checkboxes.some(function (checkbox) { return checkbox.checked; })) {
        event.preventDefault();
        if (count) count.textContent = "Choose at least one";
        checkboxes[0].focus();
      }
    });

    updateCount();
    updatePlaylist();
  });
}());
