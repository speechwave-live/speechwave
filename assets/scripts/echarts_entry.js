// Entry point for the vendored ECharts bundle. Only the pieces listed here are
// included, which keeps the bundle small. Add a piece here and rebuild when a
// new chart type or component is needed.
import { use } from "echarts/core"
import { BarChart } from "echarts/charts"
import {
  GridComponent,
  TooltipComponent,
  MarkPointComponent,
  AriaComponent,
} from "echarts/components"
import { SVGRenderer } from "echarts/renderers"
import { LabelLayout } from "echarts/features"

use([
  BarChart,
  GridComponent,
  TooltipComponent,
  MarkPointComponent,
  AriaComponent,
  SVGRenderer,
  LabelLayout,
])

export { init } from "echarts/core"
