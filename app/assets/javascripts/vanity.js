var Vanity = {}

Vanity.tooltip = function(event, pos, item) {
  if (item) {
    if (this.previousPoint != item.datapoint) {
      this.previousPoint = item.datapoint;
      $(".tooltip").remove();
      var y = item.datapoint[1].toFixed(2);
      var dt = new Date(parseInt(item.datapoint[0], 10));
      $('<div class="tooltip">' + dt.getUTCFullYear() + '-' + (dt.getUTCMonth() + 1) + '-' + dt.getUTCDate() + "<br>" +
        "<b>" + item.series.label + "</b>: " + y + '</div>').css( {
        position: 'absolute', display: 'none',
        top: item.pageY + 5, left: item.pageX + 5 - 100,
        padding: '2px', border: '1px solid #ff8', 'background-color': '#ffe', opacity: 0.9
      }).appendTo("body").fadeIn(200);
    }
  } else {
    $(".tooltip").remove();
    this.previousPoint = null;
  }
}

Vanity.retention_graph = function(id, days_ago) {
  var metric = {};
  metric.chart = $(id);
  metric.markings = [];

  var date = new Date().getTime();
  days_ago ||= 30;
  var date_ticks = [
    date - days_ago * 24 * 3600 * 1000,
    date - 3 * days_ago / 4 * 24 * 3600 * 1000,
    date - days_ago / 2 * 24 * 3600 * 1000,
    date - 1 * days_ago / 4 * 24 * 3600 * 1000,
    date,
  ];

  metric.options = {
    xaxis:  { mode: "time", ticks: date_ticks },
    series: { lines: { show: true, lineWidth: 2, fill: false, fillColor: { colors: ["#000", "#555"] } },
              points: { show: false, radius: 1 }, shadowSize: 0 },
    colors: ["#f8b144"],
    grid:   { markings: metric.markings, borderWidth: 0, hoverable: true, aboveData: true },
    legend: { show: false }
  };

  metric.plot = function(lines) {
    var min = 0, max = 0;
    $.each(lines, function(i, line) {
      $.each(line.data, function(i, pair) {
        pair[0] = Date.parse(pair[0])
        max = Math.max(max, pair[1]);
        min = Math.min(min, pair[1]);
      });
    });
    metric.options.yaxis = { ticks: [min, max] };
    var plot = $.plot(metric.chart, lines, metric.options);
    metric.chart.bind("plothover", Vanity.tooltip);
    metric.chart.data('plot', plot);
  }
  return metric;
}

function timedRefresh(timeoutPeriod) {
  setTimeout("location.reload(true);", timeoutPeriod);
}

timedRefresh(3600 * 1000);
