var Vanity = {}
Vanity.tooltip = function(event, pos, item) {
  if (item) {
    if (this.previousPoint != item.datapoint) {
      this.previousPoint = item.datapoint;
      $("#tooltip").remove();
      var y = item.datapoint[1].toFixed(2);
      var dt = new Date(parseInt(item.datapoint[0], 10));
      $('<div id="tooltip">' + dt.getUTCFullYear() + '-' + (dt.getUTCMonth() + 1) + '-' + dt.getUTCDate() + "<br>" + 
        "<b>" + item.series.label + "</b>: " + y + '</div>').css( {
        position: 'absolute', display: 'none',
        top: item.pageY + 5, left: item.pageX + 5 - 100,
        padding: '2px', border: '1px solid #ff8', 'background-color': '#ffe', opacity: 0.9
      }).appendTo("body").fadeIn(200);
    }
  } else {
    $("#tooltip").remove();
    this.previousPoint = null;            
  }
}

Vanity.metric = function(id, min, max) {
  var metric = {};
  metric.chart = $("#metric_" + id + " .chart");
  metric.chart.height(75);
  metric.markings = [];
  var date = new Date();
  var date_ticks = [
    new Date(date - 3 * 7 * 24 * 3600 * 1000).getTime(),
    new Date(date - 2 * 7 * 24 * 3600 * 1000).getTime(),
    new Date(date - 1 * 7 * 24 * 3600 * 1000).getTime(),
    date.getTime()
  ];

  metric.options = {
    xaxis:  { mode: "time", ticks: date_ticks },
    yaxis:  { ticks: [min, max] },
    series: { lines: { show: true, lineWidth: 2, fill: false, fillColor: { colors: ["#000", "#555"] } },
              points: { show: false, radius: 1 }, shadowSize: 0 },
    colors: ["#f8b144","#0ba5d9","#49cd7c"],
    legend: { position: 'sw', container: "#metric_" + id +" .legend", backgroundOpacity: 0.5 },
    grid:   { markings: metric.markings, borderWidth: 0, hoverable: true, aboveData: true } };

  metric.plot = function(lines) {
    $.each(lines, function(i, line) {
      $.each(line.data, function(i, pair) { pair[0] = Date.parse(pair[0]) })
    });
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
