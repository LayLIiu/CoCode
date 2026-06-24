/**
 * Markdown 渲染组件 - 增强版
 * 添加：表格、图片、删除线、分割线、任务列表、嵌套列表、代码折叠
 */

import { Theme } from '../common/Theme'
import pasteboard from '@ohos.pasteboard'
import { fileService } from '../services/FileService'
import { common } from '@kit.AbilityKit'

// ── 辅助类型 ──

class CodeToken {
  text: string = ''
  color: string = ''
  constructor(text: string, color: string) { this.text = text; this.color = color }
}

class TableCell {
  text: string = ''
  alignment: string = 'left'
  constructor(text: string, alignment: string = 'left') { this.text = text; this.alignment = alignment }
}

class TableRow {
  cells: TableCell[] = []
  isHeader: boolean = false
  constructor(cells: TableCell[], isHeader: boolean = false) { this.cells = cells; this.isHeader = isHeader }
}

class ParseResult {
  node: MDNode = MDNode.spacer()
  nextIdx: number = 0
  constructor(node: MDNode, nextIdx: number) { this.node = node; this.nextIdx = nextIdx }
}

class ListItemHelper {
  text: string = ''
  checked: number = -1 // -1=普通, 0=unchecked, 1=checked
  children: string[] = []
  orderNumber: number = 0
}

// ── 行内片段 ──

enum InlineFragmentType { TEXT, BOLD, ITALIC, STRIKETHROUGH, INLINE_CODE, LINK, IMG, COLOR_GREEN, COLOR_RED }

class InlineFragment {
  type: InlineFragmentType = InlineFragmentType.TEXT
  content: string = ''
  url: string = ''
  constructor(type: InlineFragmentType, content: string, url: string = '') {
    this.type = type; this.content = content; this.url = url
  }
}

// ── 节点 ──

enum MDNodeType {
  CODE_BLOCK, HEADING, UNORDERED_LIST, ORDERED_LIST,
  BLOCKQUOTE, PARAGRAPH, SPACER, TABLE, HR, IMAGE, CALLOUT
}

class MDNode {
  type: MDNodeType = MDNodeType.PARAGRAPH
  language: string = ''
  code: string = ''
  level: number = 1
  text: string = ''
  items: string[] = []
  fragments: InlineFragment[] = []
  tableRows: TableRow[] = []
  imageUrl: string = ''
  imageAlt: string = ''
  calloutTone: string = ''
  calloutTitle: string = ''
  listHelpers: ListItemHelper[] = []

  static codeBlock(lang: string, code: string): MDNode {
    const n = new MDNode(); n.type = MDNodeType.CODE_BLOCK; n.language = lang; n.code = code; return n
  }
  static heading(level: number, text: string): MDNode {
    const n = new MDNode(); n.type = MDNodeType.HEADING; n.level = level; n.text = text; return n
  }
  static unorderedList(items: string[]): MDNode {
    const n = new MDNode(); n.type = MDNodeType.UNORDERED_LIST; n.items = items; return n
  }
  static orderedList(items: string[]): MDNode {
    const n = new MDNode(); n.type = MDNodeType.ORDERED_LIST; n.items = items; return n
  }
  static blockquote(text: string): MDNode {
    const n = new MDNode(); n.type = MDNodeType.BLOCKQUOTE; n.text = text; return n
  }
  static paragraph(fragments: InlineFragment[]): MDNode {
    const n = new MDNode(); n.type = MDNodeType.PARAGRAPH; n.fragments = fragments; return n
  }
  static spacer(): MDNode {
    const n = new MDNode(); n.type = MDNodeType.SPACER; return n
  }
  static table(rows: TableRow[]): MDNode {
    const n = new MDNode(); n.type = MDNodeType.TABLE; n.tableRows = rows; return n
  }
  static hr(): MDNode {
    const n = new MDNode(); n.type = MDNodeType.HR; return n
  }
  static image(url: string, alt: string): MDNode {
    const n = new MDNode(); n.type = MDNodeType.IMAGE; n.imageUrl = url; n.imageAlt = alt; return n
  }
  static callout(tone: string, title: string, text: string): MDNode {
    const n = new MDNode(); n.type = MDNodeType.CALLOUT; n.calloutTone = tone; n.calloutTitle = title; n.text = text; return n
  }
}

// ═══════════════════════════ 组件 ═══════════════════════════

@Component
export struct MarkdownRenderer {
  @Prop @Watch('onContentChange') content: string = ''
  @Prop alignEnd: boolean = false
  @State private nodes: MDNode[] = []
  @State private expandedCodeIdx: number = -1
  @State private copiedCodeIdx: number = -1
  private copiedCodeTimer: number = -1
  onLinkClick?: (url: string) => void

  private bodyFontSize: number = 16
  private bodyLineHeight: number = 24
  private monoFontSize: number = 13
  private paragraphGap: number = 4
  private streamingCodeHighlightLimit: number = 5000

  aboutToAppear(): void { this.nodes = this.parseMarkdown(this.content) }
  onContentChange(): void { this.nodes = this.parseMarkdown(this.content) }

  private fragmentKey(frag: InlineFragment, index: number): string {
    return `${index}-${frag.type}-${frag.content.length}-${frag.url.length}`
  }

  private fragmentsSignature(fragments: InlineFragment[]): string {
    let totalLength = 0
    let typeSignature = ''
    for (let i = 0; i < fragments.length; i++) {
      totalLength += fragments[i].content.length + fragments[i].url.length
      typeSignature += fragments[i].type + '.'
    }
    return `${fragments.length}-${totalLength}-${typeSignature}`
  }

  private nodeKey(node: MDNode, index: number): string {
    if (node.type === MDNodeType.CODE_BLOCK) {
      return `md-${index}-${node.type}-${node.language}-${node.code.length}`
    }
      if (node.type === MDNodeType.HEADING || node.type === MDNodeType.BLOCKQUOTE) {
        return `md-${index}-${node.type}-${node.text.length}`
      }
      if (node.type === MDNodeType.CALLOUT) {
        return `md-${index}-${node.type}-${node.calloutTone}-${node.text.length}`
      }
    if (node.type === MDNodeType.PARAGRAPH) {
      return `md-${index}-${node.type}-${this.fragmentsSignature(node.fragments)}`
    }
    if (node.type === MDNodeType.UNORDERED_LIST || node.type === MDNodeType.ORDERED_LIST) {
      let totalLength = 0
      for (let i = 0; i < node.items.length; i++) totalLength += node.items[i].length
      return `md-${index}-${node.type}-${node.items.length}-${totalLength}`
    }
    if (node.type === MDNodeType.TABLE) {
      let totalLength = 0
      for (let r = 0; r < node.tableRows.length; r++) {
        for (let c = 0; c < node.tableRows[r].cells.length; c++) {
          totalLength += node.tableRows[r].cells[c].text.length
        }
      }
      return `md-${index}-${node.type}-${node.tableRows.length}-${totalLength}`
    }
    if (node.type === MDNodeType.IMAGE) {
      return `md-${index}-${node.type}-${node.imageUrl.length}-${node.imageAlt.length}`
    }
    return `md-${index}-${node.type}`
  }

  // ═══════════════ 解析 ═══════════════

  private parseMarkdown(text: string): MDNode[] {
    const nodes: MDNode[] = []
    const normalizedText = this.normalizeStreamingMarkdown(text)
    const lines = normalizedText.split('\n')
    let i = 0

    while (i < lines.length) {
      const line = lines[i]
      const trimmed = line.trim()

      // 代码块
      if (trimmed.startsWith('```')) {
        const lang = trimmed.substring(3).trim()
        const codeLines: string[] = []
        i++
        while (i < lines.length && !lines[i].trim().startsWith('```')) { codeLines.push(lines[i]); i++ }
        nodes.push(MDNode.codeBlock(lang, codeLines.join('\n')))
        i++
        continue
      }

      // 标题
      if (line.startsWith('#')) {
        let level = 0; let idx = 0
        while (idx < line.length && line[idx] === '#') { level++; idx++ }
        if (level >= 1 && level <= 6 && idx < line.length && line[idx] === ' ') {
          nodes.push(MDNode.heading(level, line.substring(idx + 1).trim())); i++; continue
        }
      }

      // 分割线
      if (trimmed.match(/^(-{3,}|\*{3,}|_{3,})$/)) { nodes.push(MDNode.hr()); i++; continue }

      // 表格
      if (trimmed.startsWith('|') && i + 1 < lines.length) {
        const nextTrimmed = lines[i + 1].trim()
        if (nextTrimmed.startsWith('|') && nextTrimmed.match(/^\|[\s\-:|]+\|$/)) {
          const tableRes = this.parseTable(lines, i)
          nodes.push(tableRes.node); i = tableRes.nextIdx; continue
        }
      }

      // 图片独立行
      const imgMatch = trimmed.match(/^!\[([^\]]*)\]\(([^)]+)\)$/)
      if (imgMatch) { nodes.push(MDNode.image(imgMatch[2], imgMatch[1])); i++; continue }

      // 引用
      if (trimmed.startsWith('> ')) {
        const quoteLines: string[] = []
        while (i < lines.length && lines[i].trim().startsWith('> ')) {
          quoteLines.push(lines[i].trim().substring(2).trim()); i++
        }
        nodes.push(this.buildQuoteNode(quoteLines))
        continue
      }

      // 无序列表
      if (trimmed.match(/^[-*+]\s+/)) {
        const listRes1 = this.parseList(lines, i, false)
        nodes.push(listRes1.node); i = listRes1.nextIdx; continue
      }

      // 有序列表
      if (trimmed.match(/^\d+\.\s+/)) {
        const listRes2 = this.parseList(lines, i, true)
        nodes.push(listRes2.node); i = listRes2.nextIdx; continue
      }

      // 空行
      if (trimmed === '') { nodes.push(MDNode.spacer()); i++; continue }

      const calloutNode = this.parseCalloutParagraph(trimmed)
      if (calloutNode) { nodes.push(calloutNode); i++; continue }

      // 段落
      nodes.push(MDNode.paragraph(this.parseInline(line))); i++
    }

    // 移除末尾空行
    while (nodes.length > 0 && nodes[nodes.length - 1].type === MDNodeType.SPACER) { nodes.pop() }
    return nodes
  }

  private buildQuoteNode(quoteLines: string[]): MDNode {
    if (quoteLines.length > 0) {
      const marker = quoteLines[0].match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|ERROR|SUCCESS)\]\s*$/i)
      if (marker) {
        const tone = this.normalizeCalloutTone(marker[1])
        return MDNode.callout(tone, this.getCalloutTitle(tone), quoteLines.slice(1).join('\n').trim())
      }
    }
    return MDNode.blockquote(quoteLines.join('\n'))
  }

  private parseCalloutParagraph(text: string): MDNode | null {
    const match = text.match(/^(提示|注意|重要|警告|错误|失败|成功|TODO|FIXME|NOTE|TIP|IMPORTANT|WARNING|ERROR|SUCCESS)[:：]\s*(.*)$/i)
    if (!match) return null
    const tone = this.normalizeCalloutTone(match[1])
    return MDNode.callout(tone, this.getCalloutTitle(tone), match[2])
  }

  private normalizeCalloutTone(raw: string): string {
    const value = raw.toLowerCase()
    if (value === 'warning' || value === '警告' || value === 'fixme') return 'warning'
    if (value === 'error' || value === '错误' || value === '失败') return 'error'
    if (value === 'success' || value === '成功') return 'success'
    if (value === 'important' || value === '重要' || value === 'todo') return 'important'
    return 'note'
  }

  private getCalloutTitle(tone: string): string {
    if (tone === 'warning') return '警告'
    if (tone === 'error') return '错误'
    if (tone === 'success') return '完成'
    if (tone === 'important') return '重点'
    return '提示'
  }

  private normalizeStreamingMarkdown(text: string): string {
    let result = text || ''
    if (this.countFenceMarkers(result) % 2 === 1) {
      result += '\n```'
    }
    result = this.closeUnbalancedInlineMarker(result, '**')
    result = this.closeUnbalancedInlineMarker(result, '~~')
    return result
  }

  private countFenceMarkers(text: string): number {
    let count = 0
    let index = text.indexOf('```')
    while (index >= 0) {
      count++
      index = text.indexOf('```', index + 3)
    }
    return count
  }

  private closeUnbalancedInlineMarker(text: string, marker: string): string {
    const count = this.countMarker(text, marker)
    if (count % 2 === 1) {
      return text + marker
    }
    return text
  }

  private countMarker(text: string, marker: string): number {
    let count = 0
    let index = text.indexOf(marker)
    while (index >= 0) {
      count++
      index = text.indexOf(marker, index + marker.length)
    }
    return count
  }

  // ── 表格解析 ──

  private parseTable(lines: string[], start: number): ParseResult {
    const rows: TableRow[] = []
    let i = start
    const cells0 = this.parseTableRow(lines[i])
    rows.push(new TableRow(cells0, true)); i++
    i++ // 跳过对齐行
    while (i < lines.length && lines[i].trim().startsWith('|')) {
      rows.push(new TableRow(this.parseTableRow(lines[i]), false)); i++
    }
    return new ParseResult(MDNode.table(rows), i)
  }

  private parseTableRow(line: string): TableCell[] {
    let content = line.trim()
    if (content.startsWith('|')) content = content.substring(1)
    if (content.endsWith('|')) content = content.substring(0, content.length - 1)
    const parts = content.split('|')
    const cells: TableCell[] = []
    for (let p = 0; p < parts.length; p++) cells.push(new TableCell(parts[p].trim()))
    return cells
  }

  // ── 列表解析（含任务列表） ──

  private parseList(lines: string[], start: number, ordered: boolean): ParseResult {
    const items: string[] = []
    const helpers: ListItemHelper[] = []
    let i = start
    const regex = ordered ? /^\d+\.\s+/ : /^[-*+]\s+/

    while (i < lines.length) {
      const trimmed = lines[i].trim()
      const match = trimmed.match(regex)
      if (!match) break

      let itemText = trimmed.replace(regex, '')
      const helper = new ListItemHelper()
      if (ordered) {
        const numberMatch = trimmed.match(/^(\d+)\.\s+/)
        if (numberMatch) {
          helper.orderNumber = Number(numberMatch[1])
        }
      }

      const taskMatch = itemText.match(/^\[([ xX])\]\s+(.*)/)
      if (taskMatch) {
        helper.checked = taskMatch[1].toLowerCase() === 'x' ? 1 : 0
        itemText = taskMatch[2]
      }

      helper.text = itemText
      items.push(itemText)

      i++
      while (i < lines.length) {
        const nextLine = lines[i]
        if (nextLine === '' || nextLine.trim() === '') break
        const indent = nextLine.match(/^(\s+)/)
        if (!indent || indent[1].length < 2) break
        helper.children.push(nextLine.trim().replace(/^[-*+]\s+/, ''))
        i++
      }
      helpers.push(helper)
    }

    const node = ordered ? MDNode.orderedList(items) : MDNode.unorderedList(items)
    node.listHelpers = helpers
    return new ParseResult(node, i)
  }

  // ── 行内解析（含删除线） ──

  private parseInline(text: string): InlineFragment[] {
    const fragments: InlineFragment[] = []
    let remaining = text

    while (remaining.length > 0) {
      const codeMatch = remaining.match(/`([^`]+)`/)
      if (codeMatch && codeMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.INLINE_CODE, codeMatch[1]))
        remaining = remaining.substring(codeMatch[0].length); continue
      }

      const imgMatch = remaining.match(/!\[([^\]]*)\]\(([^)]+)\)/)
      if (imgMatch && imgMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.IMG, imgMatch[1], imgMatch[2]))
        remaining = remaining.substring(imgMatch[0].length); continue
      }

      const boldMatch = remaining.match(/\*\*([^*]+)\*\*/)
      if (boldMatch && boldMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.BOLD, boldMatch[1]))
        remaining = remaining.substring(boldMatch[0].length); continue
      }

      const strikeMatch = remaining.match(/~~([^~]+)~~/)
      if (strikeMatch && strikeMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.STRIKETHROUGH, strikeMatch[1]))
        remaining = remaining.substring(strikeMatch[0].length); continue
      }

      const italicMatch = remaining.match(/\*([^*]+)\*/)
      if (italicMatch && italicMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.ITALIC, italicMatch[1]))
        remaining = remaining.substring(italicMatch[0].length); continue
      }

      const linkMatch = remaining.match(/\[([^\]]+)\]\(([^)]+)\)/)
      if (linkMatch && linkMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.LINK, linkMatch[1], linkMatch[2]))
        remaining = remaining.substring(linkMatch[0].length); continue
      }

      const greenMatch = remaining.match(/\[g\](.*?)\[\/g\]/)
      if (greenMatch && greenMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.COLOR_GREEN, greenMatch[1]))
        remaining = remaining.substring(greenMatch[0].length); continue
      }

      const redMatch = remaining.match(/\[r\](.*?)\[\/r\]/)
      if (redMatch && redMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.COLOR_RED, redMatch[1]))
        remaining = remaining.substring(redMatch[0].length); continue
      }

      const nextSpecial = this.findNextSpecial(remaining)
      if (nextSpecial > 0) {
        fragments.push(new InlineFragment(InlineFragmentType.TEXT, remaining.substring(0, nextSpecial)))
        remaining = remaining.substring(nextSpecial)
      } else if (nextSpecial === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.TEXT, remaining.charAt(0)))
        remaining = remaining.substring(1)
      } else {
        fragments.push(new InlineFragment(InlineFragmentType.TEXT, remaining)); remaining = ''
      }
    }
    return fragments
  }

  private findNextSpecial(text: string): number {
    let pos = -1
    const chars = ['`', '*', '[', '!', '~']
    for (let i = 0; i < chars.length; i++) {
      const idx = text.indexOf(chars[i])
      if (idx >= 0 && (pos < 0 || idx < pos)) pos = idx
    }
    return pos
  }

  // ── 代码文本分段 ──

  private getCodeTokens(code: string, lang: string): CodeToken[] {
    const tokens: CodeToken[] = []
    if (!lang || lang === 'plaintext' || lang === 'text') {
      tokens.push(new CodeToken(code, '#E8E8EC'))
      return tokens
    }

    const keywords = [
      'import', 'export', 'from', 'const', 'let', 'var', 'function', 'return',
      'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
      'new', 'this', 'class', 'extends', 'implements', 'interface', 'type',
      'public', 'private', 'protected', 'static', 'async', 'await', 'try',
      'catch', 'finally', 'throw', 'typeof', 'instanceof', 'void', 'null',
      'true', 'false', 'undefined', 'enum', 'namespace', 'abstract', 'readonly',
      'as', 'is', 'keyof', 'never', 'any', 'struct', 'constructor', 'super'
    ]

    let remaining = code
    while (remaining.length > 0) {
      // 单行注释
      if (remaining.startsWith('//')) {
        const end = remaining.indexOf('\n')
        const comment = end >= 0 ? remaining.substring(0, end) : remaining
        tokens.push(new CodeToken(comment, '#8E8E93'))
        remaining = end >= 0 ? remaining.substring(end) : ''; continue
      }
      // 多行注释
      if (remaining.startsWith('/*')) {
        const end = remaining.indexOf('*/')
        if (end >= 0) {
          tokens.push(new CodeToken(remaining.substring(0, end + 2), '#8E8E93'))
          remaining = remaining.substring(end + 2)
        } else { tokens.push(new CodeToken(remaining, '#8E8E93')); remaining = '' }
        continue
      }
      // 字符串
      const strMatch = remaining.match(/^(["'`])(?:\\.|[^\\])*?\1/)
      if (strMatch) {
        tokens.push(new CodeToken(strMatch[0], '#E8E8EC'))
        remaining = remaining.substring(strMatch[0].length); continue
      }
      // 数字
      const numMatch = remaining.match(/^\b\d+(\.\d+)?\b/)
      if (numMatch) {
        tokens.push(new CodeToken(numMatch[0], '#E8E8EC'))
        remaining = remaining.substring(numMatch[0].length); continue
      }
      // 关键字
      let found = false
      for (let k = 0; k < keywords.length; k++) {
        const kwRegex = new RegExp('^' + keywords[k] + '\\b')
        const kwMatch = remaining.match(kwRegex)
        if (kwMatch) {
          tokens.push(new CodeToken(kwMatch[0], '#F2F2F7'))
          remaining = remaining.substring(kwMatch[0].length)
          found = true; break
        }
      }
      if (found) continue
      // 普通
      const idx = this.findCodeBreak(remaining)
      if (idx > 0) {
        tokens.push(new CodeToken(remaining.substring(0, idx), '#E8E8EC'))
        remaining = remaining.substring(idx)
      } else { tokens.push(new CodeToken(remaining, '#E8E8EC')); remaining = '' }
    }
    return tokens
  }

  private findCodeBreak(text: string): number {
    let pos = -1
    const markers = ['//', '"', "'", '`']
    for (let i = 0; i < markers.length; i++) {
      const idx = text.indexOf(markers[i], 1)
      if (idx > 0 && (pos < 0 || idx < pos)) pos = idx
    }
    return pos
  }

  // ═══════════════ 构建 ═══════════════

  build() {
    Column() {
      ForEach(this.nodes, (node: MDNode, index: number) => {
        if (node.type === MDNodeType.CODE_BLOCK) { this.CodeBlockView(node, index)
        } else if (node.type === MDNodeType.HEADING) { this.HeadingView(node)
        } else if (node.type === MDNodeType.UNORDERED_LIST) { this.UnorderedListView(node)
        } else if (node.type === MDNodeType.ORDERED_LIST) { this.OrderedListView(node)
        } else if (node.type === MDNodeType.BLOCKQUOTE) { this.BlockquoteView(node)
        } else if (node.type === MDNodeType.CALLOUT) { this.CalloutView(node)
        } else if (node.type === MDNodeType.TABLE) { this.TableView(node)
        } else if (node.type === MDNodeType.HR) { this.HorizontalRuleView()
        } else if (node.type === MDNodeType.IMAGE) { this.ImageView(node)
        } else if (node.type === MDNodeType.PARAGRAPH) { this.ParagraphView(node)
        } else if (node.type === MDNodeType.SPACER) { Row().height(10) }
      }, (node: MDNode, index: number) => this.nodeKey(node, index))
    }
    .width('100%')
    .alignItems(this.alignEnd ? HorizontalAlign.End : HorizontalAlign.Start)
    .clip(false)
  }

  // ── 代码块 ──

  @Builder
  CodeBlockView(node: MDNode, idx: number) {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text(node.language ? node.language.toLowerCase() : 'code')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(Theme.TextSecondary)

        Blank()

        if (this.copiedCodeIdx === idx) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(15)
            .fontColor(['rgba(255, 255, 255, 0.55)'])
        } else {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(15)
            .fontColor([Theme.TextTertiary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 11, bottom: 4 })
      .onClick(() => { this.copyCodeWithFeedback(node.code, idx) })

      Scroll() {
        if (this.shouldRenderPlainCode(node)) {
          Text(node.code)
            .fontSize(this.monoFontSize)
            .fontFamily('monospace')
            .fontColor('#E8E8EC')
            .lineHeight(20)
        } else if (node.language && node.language !== 'plaintext' && node.language !== 'text') {
          Text() {
            ForEach(this.getCodeTokens(node.code, node.language), (token: CodeToken, ti: number) => {
              Span(token.text).fontSize(this.monoFontSize).fontFamily('monospace').fontColor(token.color)
            }, (token: CodeToken, ti: number) => `ct-${ti}`)
          }
          .lineHeight(20)
        } else {
          Text(node.code)
            .fontSize(this.monoFontSize)
            .fontFamily('monospace')
            .fontColor('#E8E8EC')
            .lineHeight(20)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
      .padding({ left: 12, right: 12, top: 6, bottom: 12 })
      .constraintSize({ maxHeight: this.shouldCollapseCode(node) && this.expandedCodeIdx !== idx ? 360 : 5000 })

      if (this.shouldCollapseCode(node) && this.expandedCodeIdx !== idx) {
        Row({ space: 6 }) {
          Text('展开完整代码')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextSecondary)

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(11)
            .fontColor([Theme.TextSecondary])
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 7, bottom: 10 })
        .onClick(() => { this.expandedCodeIdx = idx })
      }
    }
    .width('100%')
    .backgroundColor('rgba(42, 42, 46, 0.96)')
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.12)' })
    .borderRadius(10)
    .margin({ top: 8, bottom: 8 })
    .clip(true)
  }

  private shouldCollapseCode(node: MDNode): boolean {
    return node.code.split('\n').length > 60
  }

  private shouldRenderPlainCode(node: MDNode): boolean {
    return node.code.length > this.streamingCodeHighlightLimit
  }

  private getCodeLineCount(node: MDNode): number {
    return node.code.split('\n').length
  }

  private copyCodeWithFeedback(code: string, idx: number): void {
    try {
      const sp = pasteboard.getSystemPasteboard()
      sp.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code))
    } catch (e) { /* ignore */ }
    this.copiedCodeIdx = idx
    if (this.copiedCodeTimer !== -1) {
      clearTimeout(this.copiedCodeTimer)
    }
    this.copiedCodeTimer = setTimeout(() => {
      this.copiedCodeIdx = -1
      this.copiedCodeTimer = -1
    }, 1500)
  }

  // ── 标题 ──

  @Builder
  HeadingView(node: MDNode) {
    Text(node.text)
      .fontSize(node.level <= 2 ? 18 : 16)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.TextPrimary)
      .lineHeight(node.level <= 2 ? 24 : 22)
      .width('100%')
      .margin({ top: node.level === 1 ? 12 : 8, bottom: 4 })
  }

  // ── 表格 ──

  @Builder
  TableView(node: MDNode) {
    Scroll() {
      Column({ space: 0 }) {
        ForEach(node.tableRows, (row: TableRow, ri: number) => {
          Row({ space: 1 }) {
            ForEach(row.cells, (cell: TableCell, ci: number) => {
              Text() {
                ForEach(this.parseInline(cell.text), (frag: InlineFragment, fi: number) => {
                  this.renderInlineFragment(frag)
                }, (frag: InlineFragment, fi: number) => `tc${ri}-${ci}-${this.fragmentKey(frag, fi)}`)
              }
              .fontSize(12).fontWeight(row.isHeader ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(row.isHeader ? Theme.TextPrimary : Theme.TextSecondary)
              .textAlign(cell.alignment === 'center' ? TextAlign.Center :
                cell.alignment === 'right' ? TextAlign.End : TextAlign.Start)
              .layoutWeight(1).padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .backgroundColor(row.isHeader ? 'rgba(255,255,255,0.035)' : 'transparent')
            }, (cell: TableCell, ci: number) => `tc-${ri}-${ci}`)
          }
          .width('100%')
        }, (row: TableRow, ri: number) => `tr-${ri}`)
      }
      .width('100%')
      .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
      .borderRadius(10)
      .backgroundColor('rgba(255,255,255,0.025)')
      .margin({ top: 6, bottom: 6 })
      .clip(true)
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
  }

  // ── 图片 ──

  /** 从服务端获取的图片缓存 url → dataUri */
  private imageFetchCache: Map<string, string> = new Map()

  /**
   * 解析图片 URL：远程 URL 直接返回，本地路径从服务端拉取
   */
  private async resolveImageUrl(url: string): Promise<string> {
    if (!url || !this.isSafeMediaUrl(url)) return ''
    if (fileService.isRemoteUrl(url)) return url

    const cached = this.imageFetchCache.get(url)
    if (cached) return cached

    try {
      const dataUri = await fileService.fetchImageBase64(url)
      if (dataUri) {
        this.imageFetchCache.set(url, dataUri)
        return dataUri
      }
    } catch (e) {
      console.error('[Markdown] resolveImageUrl error:', e)
    }
    return url
  }

  @Builder
  ImageView(node: MDNode) {
    Column({ space: 3 }) {
      if (node.imageUrl) {
        AsyncImage({
          url: node.imageUrl,
          resolver: (u: string) => this.resolveImageUrl(u),
          alt: node.imageAlt
        })
      }
      if (node.imageAlt) {
        Text(node.imageAlt).fontSize(11).fontColor(Theme.TextTertiary).textAlign(TextAlign.Center)
      }
    }
    .width('100%').borderRadius(10).margin({ top: 2, bottom: 2 })
  }

  // ── 分割线 ──

  @Builder
  HorizontalRuleView() {
    Divider().color('rgba(255,255,255,0.12)').width('100%').margin({ top: 12, bottom: 12 })
  }

  // ── 段落 ──

  // 检查段落中是否有需要特殊处理的片段（链接、图片）
  private hasSpecialFragment(fragments: InlineFragment[]): boolean {
    for (let i = 0; i < fragments.length; i++) {
      if (fragments[i].type === InlineFragmentType.LINK || fragments[i].type === InlineFragmentType.IMG) {
        return true
      }
    }
    return false
  }

  // 打开链接（通过回调或系统浏览器）
  private openLink(url: string): void {
    try {
      const safeUrl = this.safeLinkUrl(url)
      if (!safeUrl) return
      if (this.onLinkClick) {
        this.onLinkClick(safeUrl)
      } else {
        // 默认：通过系统 Intent 打开
        let context = getContext(this) as common.UIAbilityContext
        context.startAbility({
          action: 'ohos.want.action.viewData',
          uri: safeUrl,
          type: 'text/html'
        }).catch((err: Error) => {
          console.error('[Markdown] Open link error:', err.message)
        })
      }
    } catch (e) {
      console.error('[Markdown] Open link error:', e)
    }
  }

  private safeLinkUrl(url: string): string {
    const trimmed = (url || '').trim()
    const lower = trimmed.toLowerCase()
    if (lower.startsWith('javascript:') || lower.startsWith('data:') || lower.startsWith('vbscript:')) return ''
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('file://')) return trimmed
    if (lower.startsWith('/')) return trimmed
    return ''
  }

  private isSafeMediaUrl(url: string): boolean {
    const trimmed = (url || '').trim().toLowerCase()
    return trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('file://') ||
      trimmed.startsWith('data:image/') ||
      trimmed.startsWith('/')
  }

  @Builder
  ParagraphView(node: MDNode) {
    if (node.fragments.length === 0) { Text('') } else if (this.hasSpecialFragment(node.fragments)) {
      Column() {
        this.ClickableParagraph(node.fragments)
      }
      .width('100%')
    } else {
      Text() {
        ForEach(node.fragments, (frag: InlineFragment, fi: number) => {
          this.renderInlineFragment(frag)
        }, (frag: InlineFragment, fi: number) => this.fragmentKey(frag, fi))
      }
      .fontSize(this.bodyFontSize)
      .fontColor(Theme.TextPrimary)
      .lineHeight(this.bodyLineHeight)
      .width('100%')
      .margin({ bottom: this.paragraphGap })
    }
  }

  @Builder
  ClickableParagraph(fragments: InlineFragment[]) {
    Text() {
      ForEach(fragments, (frag: InlineFragment, fi: number) => {
        if (frag.type === InlineFragmentType.LINK) {
          Span(frag.content).fontSize(this.bodyFontSize).fontColor(Theme.AccentBlue)
        } else if (frag.type === InlineFragmentType.IMG) {
          Span('[图片]').fontSize(13).fontColor(Theme.TextTertiary)
        } else {
          this.renderInlineFragment(frag)
        }
      }, (frag: InlineFragment, fi: number) => this.fragmentKey(frag, fi))
    }
    .fontSize(this.bodyFontSize)
    .fontColor(Theme.TextPrimary)
    .lineHeight(this.bodyLineHeight)
    .width('100%')
    .margin({ bottom: this.paragraphGap })
    .onClick((event: ClickEvent) => {
      // 点击段落时检测是否点到链接
      // 由于无法精确检测哪个 Span 被点击，遍历所有 LINK 片段
      for (let i = 0; i < fragments.length; i++) {
        if (fragments[i].type === InlineFragmentType.LINK) {
          this.openLink(fragments[i].url)
          break // 打开第一个链接
        }
      }
    })
  }

  @Builder
  renderInlineFragment(frag: InlineFragment) {
    if (frag.type === InlineFragmentType.BOLD) {
      Span(frag.content).fontSize(this.bodyFontSize).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
    } else if (frag.type === InlineFragmentType.ITALIC) {
      Span(frag.content).fontSize(this.bodyFontSize).fontStyle(FontStyle.Italic).fontColor(Theme.TextPrimary)
    } else if (frag.type === InlineFragmentType.STRIKETHROUGH) {
      Span(frag.content).fontSize(this.bodyFontSize).fontColor(Theme.TextTertiary)
        .decoration({ type: TextDecorationType.LineThrough })
    } else if (frag.type === InlineFragmentType.INLINE_CODE) {
      Span(' ' + frag.content + ' ').fontSize(13).fontFamily('monospace')
        .fontColor(Theme.TextSecondary).fontWeight(FontWeight.Medium)
    } else if (frag.type === InlineFragmentType.LINK) {
      Span(frag.content).fontSize(this.bodyFontSize).fontColor(Theme.AccentBlue)
    } else if (frag.type === InlineFragmentType.IMG) {
      Span('[图片:' + frag.content + ']').fontSize(13).fontColor(Theme.TextTertiary)
    } else if (frag.type === InlineFragmentType.COLOR_GREEN) {
      Span(frag.content).fontSize(this.bodyFontSize).fontWeight(FontWeight.Medium).fontColor('#7EDC91')
    } else if (frag.type === InlineFragmentType.COLOR_RED) {
      Span(frag.content).fontSize(this.bodyFontSize).fontWeight(FontWeight.Medium).fontColor('#FF8A80')
    } else {
      Span(frag.content).fontSize(this.bodyFontSize).fontColor(Theme.TextPrimary)
    }
  }

  // ── 无序列表（含任务列表、嵌套） ──

  @Builder
  UnorderedListView(node: MDNode) {
    Column() {
      ForEach(node.items, (item: string, itemIdx: number) => {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            this.ListBullet(node, itemIdx)
            this.InlineFormattedText(item)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          this.ListChildrenView(node, itemIdx)
        }
        .width('100%')
        .margin({ bottom: 5 })
      }, (item: string, itemIdx: number) => `ul-${itemIdx}-${item.length}`)
    }
    .width('100%').padding({ left: 1 }).margin({ top: 3, bottom: 7 })
  }

  @Builder
  ListBullet(node: MDNode, itemIdx: number) {
    if (node.listHelpers.length > itemIdx && node.listHelpers[itemIdx].checked >= 0) {
      if (node.listHelpers[itemIdx].checked === 1) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(16).fontColor([Theme.TextSecondary])
      } else {
        SymbolGlyph($r('sys.symbol.circle')).fontSize(16).fontColor([Theme.TextTertiary])
      }
    } else {
      Text('•').fontSize(16).fontColor(Theme.TextTertiary).lineHeight(this.bodyLineHeight)
    }
  }

  // ── 有序列表 ──

  @Builder
  OrderedListView(node: MDNode) {
    Column() {
      ForEach(node.items, (item: string, itemIdx: number) => {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(this.getOrderedListNumber(node, itemIdx) + '.').fontSize(15).fontColor(Theme.TextTertiary).width(22).textAlign(TextAlign.End).lineHeight(this.bodyLineHeight)
            this.InlineFormattedText(item)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          this.ListChildrenView(node, itemIdx)
        }
        .width('100%')
        .margin({ bottom: 5 })
      }, (item: string, itemIdx: number) => `ol-${itemIdx}-${item.length}`)
    }
    .width('100%').padding({ left: 1 }).margin({ top: 3, bottom: 7 })
  }

  private getOrderedListNumber(node: MDNode, itemIdx: number): number {
    if (node.listHelpers.length > itemIdx && node.listHelpers[itemIdx].orderNumber > 0) {
      return node.listHelpers[itemIdx].orderNumber
    }
    return itemIdx + 1
  }

  @Builder
  ListChildrenView(node: MDNode, itemIdx: number) {
    if (node.listHelpers.length > itemIdx && node.listHelpers[itemIdx].children.length > 0) {
      Column({ space: 3 }) {
        ForEach(node.listHelpers[itemIdx].children, (child: string, childIdx: number) => {
          Row({ space: 6 }) {
            Text('–')
              .fontSize(13)
              .fontColor(Theme.TextTertiary)
              .width(16)
              .textAlign(TextAlign.End)
              .lineHeight(22)
            this.InlineFormattedText(child)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (child: string, childIdx: number) => `child-${itemIdx}-${childIdx}-${child.length}`)
      }
      .width('100%')
      .padding({ left: 24 })
    }
  }

  // ── 引用 ──

  @Builder
  BlockquoteView(node: MDNode) {
    Row({ space: 10 }) {
      Column().width(3).height('100%').backgroundColor('rgba(140, 140, 145, 0.42)').borderRadius(2)
      Text(node.text).fontSize(15).fontColor(Theme.TextSecondary).lineHeight(22).layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('rgba(255,255,255,0.04)')
    .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
    .borderRadius(10)
    .margin({ top: 6, bottom: 6 })
  }

  @Builder
  CalloutView(node: MDNode) {
    Row({ space: 10 }) {
      Column()
        .width(3)
        .height('100%')
        .backgroundColor(this.getCalloutAccentColor(node.calloutTone))
        .borderRadius(2)

      Column({ space: 5 }) {
        Text(this.getCalloutTitle(node.calloutTone))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getCalloutTextColor(node.calloutTone))
          .width('100%')

        if (node.text.length > 0) {
          Text() {
            ForEach(this.parseInline(node.text), (frag: InlineFragment, fi: number) => {
              this.renderInlineFragment(frag)
            }, (frag: InlineFragment, fi: number) => this.fragmentKey(frag, fi))
          }
          .fontSize(this.bodyFontSize)
          .fontColor(Theme.TextPrimary)
          .lineHeight(this.bodyLineHeight)
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 11, right: 11, top: 10, bottom: 10 })
    .backgroundColor(this.getCalloutBackgroundColor(node.calloutTone))
    .border({ width: 0.5, color: this.getCalloutBorderColor(node.calloutTone) })
    .borderRadius(10)
    .margin({ top: 6, bottom: 6 })
  }

  private getCalloutAccentColor(tone: string): string {
    if (tone === 'warning') return '#F0B04E'
    if (tone === 'error') return '#F17F77'
    if (tone === 'success') return '#6FCB87'
    if (tone === 'important') return '#9E8BFF'
    return '#77AFFF'
  }

  private getCalloutTextColor(tone: string): string {
    if (tone === 'warning') return '#F8D69A'
    if (tone === 'error') return '#F7B0AA'
    if (tone === 'success') return '#B4E6BF'
    if (tone === 'important') return '#D2C6FF'
    return '#BBD4FF'
  }

  private getCalloutBackgroundColor(tone: string): string {
    if (tone === 'warning') return 'rgba(240,176,78,0.10)'
    if (tone === 'error') return 'rgba(241,127,119,0.10)'
    if (tone === 'success') return 'rgba(111,203,135,0.09)'
    if (tone === 'important') return 'rgba(158,139,255,0.09)'
    return 'rgba(119,175,255,0.09)'
  }

  private getCalloutBorderColor(tone: string): string {
    if (tone === 'warning') return 'rgba(240,176,78,0.22)'
    if (tone === 'error') return 'rgba(241,127,119,0.22)'
    if (tone === 'success') return 'rgba(111,203,135,0.18)'
    if (tone === 'important') return 'rgba(158,139,255,0.20)'
    return 'rgba(119,175,255,0.20)'
  }

  // ── 列表行内格式 ──

  @Builder
  InlineFormattedText(text: string) {
    Text() {
      ForEach(this.parseInline(text), (frag: InlineFragment, fi: number) => {
        this.renderInlineFragment(frag)
      }, (frag: InlineFragment, fi: number) => this.fragmentKey(frag, fi))
    }
    .fontSize(this.bodyFontSize)
    .fontColor(Theme.TextPrimary)
    .lineHeight(this.bodyLineHeight)
    .layoutWeight(1)
  }
}

// ── 异步图片加载组件 ──

@Component
struct AsyncImage {
  url: string = ''
  resolver: (url: string) => Promise<string> = async (u) => u
  alt: string = ''
  @State private resolvedSrc: string = ''
  @State private isLoading: boolean = true
  @State private hasError: boolean = false

  aboutToAppear(): void {
    this.loadImage()
  }

  private async loadImage(): Promise<void> {
    if (!this.url) {
      this.isLoading = false
      this.hasError = true
      return
    }
    this.isLoading = true
    this.hasError = false
    try {
      const src = await this.resolver(this.url)
      if (src) {
        this.resolvedSrc = src
      } else {
        this.hasError = true
      }
    } catch (e) {
      this.hasError = true
    }
    this.isLoading = false
  }

  build() {
    Column({ space: 4 }) {
      if (this.isLoading) {
        Row({ space: 6 }) {
          Text('⬇')
            .fontSize(16)
          Text('加载图片...')
            .fontSize(12)
            .fontColor(Theme.TextTertiary)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .height(72)
        .backgroundColor('rgba(255,255,255,0.03)')
        .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
        .borderRadius(10)

      } else if (this.hasError) {
        Row({ space: 6 }) {
          Text('⚠')
            .fontSize(16)
          Text('图片加载失败')
            .fontSize(12)
            .fontColor(Theme.TextTertiary)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .height(56)
        .backgroundColor('rgba(255,255,255,0.03)')
        .border({ width: 0.5, color: 'rgba(255,255,255,0.08)' })
        .borderRadius(10)
        .onClick(() => { this.loadImage() })

      } else if (this.resolvedSrc) {
        Image(this.resolvedSrc)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius(10)
          .constraintSize({ maxHeight: 180 })
          .backgroundColor('rgba(0,0,0,0.12)')
      }

      if (this.alt) {
        Text(this.alt)
          .fontSize(11)
          .fontColor(Theme.TextTertiary)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
  }
}
