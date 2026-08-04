import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const BASE_OPTIONS = {
  responsive: true,
  maintainAspectRatio: false,
  animation: false,
  plugins: { legend: { display: false } },
  scales: {
    x: {
      display: true,
      grid: { display: false },
      ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 4 },
    },
    y: { beginAtZero: true },
  },
}

/**
 * Two line charts that each show a single snapshot point per update (manual refresh).
 * Prevents unbounded history and pairs each series with its own labels.
 */
export class SnapshotChartsPanel {
  /**
   * @param {HTMLCanvasElement} memoryCanvas
   * @param {HTMLCanvasElement} loadCanvas
   * @param {{ rss_mb?: string, load_1m?: string }} [chartLabels] — from I18n admin.system_monitoring.charts
   */
  constructor(memoryCanvas, loadCanvas, chartLabels = {}) {
    const rssLabel = chartLabels.rss_mb || "RSS (MB)"
    const loadLabel = chartLabels.load_1m || "Load 1m"
    this.memoryChart = new Chart(memoryCanvas.getContext("2d"), {
      type: "line",
      data: {
        labels: [],
        datasets: [
          {
            label: rssLabel,
            data: [],
            borderColor: "rgb(59, 130, 246)",
            backgroundColor: "rgba(59, 130, 246, 0.2)",
            fill: false,
            tension: 0.2,
            pointRadius: 6,
            pointHoverRadius: 8,
          },
        ],
      },
      options: BASE_OPTIONS,
    })

    this.loadChart = new Chart(loadCanvas.getContext("2d"), {
      type: "line",
      data: {
        labels: [],
        datasets: [
          {
            label: loadLabel,
            data: [],
            borderColor: "rgb(34, 197, 94)",
            backgroundColor: "rgba(34, 197, 94, 0.2)",
            fill: false,
            tension: 0.2,
            pointRadius: 6,
            pointHoverRadius: 8,
          },
        ],
      },
      options: BASE_OPTIONS,
    })
  }

  /**
   * @param {{ rssMb: number|null, load1m: number|null, timeLabel: string }} snap
   */
  setSnapshot(snap) {
    const { rssMb, load1m, timeLabel } = snap
    const label = timeLabel || "—"

    if (rssMb != null) {
      this.memoryChart.data.labels = [label]
      this.memoryChart.data.datasets[0].data = [rssMb]
    } else {
      this.memoryChart.data.labels = []
      this.memoryChart.data.datasets[0].data = []
    }
    this.memoryChart.update("none")

    if (load1m != null) {
      this.loadChart.data.labels = [label]
      this.loadChart.data.datasets[0].data = [load1m]
    } else {
      this.loadChart.data.labels = []
      this.loadChart.data.datasets[0].data = []
    }
    this.loadChart.update("none")
  }

  destroy() {
    this.memoryChart?.destroy()
    this.loadChart?.destroy()
    this.memoryChart = null
    this.loadChart = null
  }
}
