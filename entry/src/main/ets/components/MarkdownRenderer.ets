/**
 * Markdown 渲染组件 - 增强版
 * 添加：表格、图片、删除线、分割线、任务列表、嵌套列表、代码折叠、关键字着色
 */

import { Theme } from '../common/Theme'
import pasteboard from '@ohos.pasteboard'
import { fileService } from '../services/FileService'

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
  BLOCKQUOTE, PARAGRAPH, SPACER, TABLE, HR, IMAGE
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
}

// ═══════════════════════════ 组件 ═══════════════════════════

@Component
export struct MarkdownRenderer {
  @Prop @Watch('onContentChange') content: string = ''
  @State private nodes: MDNode[] = []
  @State private expandedCodeIdx: number = -1

  aboutToAppear(): void { this.nodes = this.parseMarkdown(this.content) }
  onContentChange(): void { this.nodes = this.parseMarkdown(this.content) }

  // ═══════════════ 解析 ═══════════════

  private parseMarkdown(text: string): MDNode[] {
    const nodes: MDNode[] = []
    const lines = text.split('\n')
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
        nodes.push(MDNode.blockquote(quoteLines.join('\n')))
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

      // 段落
      nodes.push(MDNode.paragraph(this.parseInline(line))); i++
    }

    // 移除末尾空行
    while (nodes.length > 0 && nodes[nodes.length - 1].type === MDNodeType.SPACER) { nodes.pop() }
    return nodes
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

  // ── 代码关键字着色 ──

  private getCodeTokens(code: string, lang: string): CodeToken[] {
    const tokens: CodeToken[] = []
    if (!lang || lang === 'plaintext' || lang === 'text') {
      tokens.push(new CodeToken(code, '#FFFFFFE6'))
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
        tokens.push(new CodeToken(comment, '#6A9955'))
        remaining = end >= 0 ? remaining.substring(end) : ''; continue
      }
      // 多行注释
      if (remaining.startsWith('/*')) {
        const end = remaining.indexOf('*/')
        if (end >= 0) {
          tokens.push(new CodeToken(remaining.substring(0, end + 2), '#6A9955'))
          remaining = remaining.substring(end + 2)
        } else { tokens.push(new CodeToken(remaining, '#6A9955')); remaining = '' }
        continue
      }
      // 字符串
      const strMatch = remaining.match(/^(["'`])(?:\\.|[^\\])*?\1/)
      if (strMatch) {
        tokens.push(new CodeToken(strMatch[0], '#CE9178'))
        remaining = remaining.substring(strMatch[0].length); continue
      }
      // 数字
      const numMatch = remaining.match(/^\b\d+(\.\d+)?\b/)
      if (numMatch) {
        tokens.push(new CodeToken(numMatch[0], '#B5CEA8'))
        remaining = remaining.substring(numMatch[0].length); continue
      }
      // 关键字
      let found = false
      for (let k = 0; k < keywords.length; k++) {
        const kwRegex = new RegExp('^' + keywords[k] + '\\b')
        const kwMatch = remaining.match(kwRegex)
        if (kwMatch) {
          tokens.push(new CodeToken(kwMatch[0], '#569CD6'))
          remaining = remaining.substring(kwMatch[0].length)
          found = true; break
        }
      }
      if (found) continue
      // 普通
      const idx = this.findCodeBreak(remaining)
      if (idx > 0) {
        tokens.push(new CodeToken(remaining.substring(0, idx), '#FFFFFFE6'))
        remaining = remaining.substring(idx)
      } else { tokens.push(new CodeToken(remaining, '#FFFFFFE6')); remaining = '' }
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
        } else if (node.type === MDNodeType.TABLE) { this.TableView(node)
        } else if (node.type === MDNodeType.HR) { this.HorizontalRuleView()
        } else if (node.type === MDNodeType.IMAGE) { this.ImageView(node)
        } else if (node.type === MDNodeType.PARAGRAPH) { this.ParagraphView(node)
        } else if (node.type === MDNodeType.SPACER) { Row().height(2) }
      }, (node: MDNode, index: number) => `md-${index}`)
    }
    .width('100%')
  }

  // ── 代码块 ──

  @Builder
  CodeBlockView(node: MDNode, idx: number) {
    Column({ space: 0 }) {
      Row() {
        Row({ space: 6 }) {
          Text(node.language ? node.language.toLowerCase() : 'code')
            .fontSize(11).fontWeight(FontWeight.Medium).fontFamily('monospace').fontColor('#FFFFFF99')
          if (this.shouldCollapseCode(node)) {
            Text(this.getCodeLineCount(node) + ' lines').fontSize(10).fontColor('#FFFFFF66')
          }
        }
        Blank()
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(11).fontColor(['#FFFFFF99'])
      }
      .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius({ topLeft: 8, topRight: 8 })
      .onClick(() => { this.copyCode(node.code) })

      Scroll() {
        if (node.language && node.language !== 'plaintext' && node.language !== 'text') {
          Text() {
            ForEach(this.getCodeTokens(node.code, node.language), (token: CodeToken, ti: number) => {
              Span(token.text).fontSize(13).fontFamily('monospace').fontColor(token.color)
            }, (token: CodeToken, ti: number) => `ct-${ti}`)
          }
        } else {
          Text(node.code).fontSize(13).fontFamily('monospace').fontColor('#FFFFFFE6')
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .constraintSize({ maxHeight: this.shouldCollapseCode(node) && this.expandedCodeIdx !== idx ? 280 : 5000 })

      if (this.shouldCollapseCode(node) && this.expandedCodeIdx !== idx) {
        Row({ space: 4 }) {
          Text('展开全部').fontSize(11).fontColor(Theme.AccentBlue)
        }
        .width('100%').justifyContent(FlexAlign.Center).padding({ top: 2, bottom: 6 })
        .onClick(() => { this.expandedCodeIdx = idx })
      }
    }
    .width('100%').borderRadius(8).margin({ top: 3, bottom: 3 }).clip(true)
  }

  private shouldCollapseCode(node: MDNode): boolean {
    return node.code.split('\n').length > 20
  }

  private getCodeLineCount(node: MDNode): number {
    return node.code.split('\n').length
  }

  private copyCode(code: string): void {
    try {
      const sp = pasteboard.getSystemPasteboard()
      sp.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code))
    } catch (e) { /* ignore */ }
  }

  // ── 标题 ──

  @Builder
  HeadingView(node: MDNode) {
    Text(node.text)
      .fontSize(22 - node.level * 2).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
      .width('100%').margin({ top: node.level === 1 ? 6 : 3, bottom: 1 })
  }

  // ── 表格 ──

  @Builder
  TableView(node: MDNode) {
    Column({ space: 0 }) {
      ForEach(node.tableRows, (row: TableRow, ri: number) => {
        Row({ space: 1 }) {
          ForEach(row.cells, (cell: TableCell, ci: number) => {
            Text() {
              ForEach(this.parseInline(cell.text), (frag: InlineFragment, fi: number) => {
                this.renderInlineFragment(frag)
              }, (frag: InlineFragment, fi: number) => `tc${ri}-${ci}-${fi}`)
            }
            .fontSize(13).fontWeight(row.isHeader ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(Theme.TextPrimary)
            .textAlign(cell.alignment === 'center' ? TextAlign.Center :
              cell.alignment === 'right' ? TextAlign.End : TextAlign.Start)
            .layoutWeight(1).padding({ left: 6, right: 6, top: 4, bottom: 4 })
          }, (cell: TableCell, ci: number) => `tc-${ri}-${ci}`)
        }
        .width('100%')
      }, (row: TableRow, ri: number) => `tr-${ri}`)
    }
    .width('100%').border({ width: 0.5, color: '#FFFFFF1A' }).borderRadius(8)
    .margin({ top: 3, bottom: 3 }).clip(true)
  }

  // ── 图片 ──

  /** 从服务端获取的图片缓存 url → dataUri */
  private imageFetchCache: Map<string, string> = new Map()

  /**
   * 解析图片 URL：远程 URL 直接返回，本地路径从服务端拉取
   */
  private async resolveImageUrl(url: string): Promise<string> {
    if (!url) return ''
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
    Column({ space: 4 }) {
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
    .width('100%').borderRadius(8).margin({ top: 3, bottom: 3 })
  }

  // ── 分割线 ──

  @Builder
  HorizontalRuleView() {
    Divider().color('#FFFFFF33').width('100%').margin({ top: 6, bottom: 6 })
  }

  // ── 段落 ──

  @Builder
  ParagraphView(node: MDNode) {
    if (node.fragments.length === 0) { Text('') } else {
      Text() {
        ForEach(node.fragments, (frag: InlineFragment, fi: number) => {
          this.renderInlineFragment(frag)
        }, (frag: InlineFragment, fi: number) => `frag-${fi}`)
      }
      .lineHeight(20).width('100%')
    }
  }

  @Builder
  renderInlineFragment(frag: InlineFragment) {
    if (frag.type === InlineFragmentType.BOLD) {
      Span(frag.content).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
    } else if (frag.type === InlineFragmentType.ITALIC) {
      Span(frag.content).fontSize(15).fontStyle(FontStyle.Italic).fontColor(Theme.TextPrimary)
    } else if (frag.type === InlineFragmentType.STRIKETHROUGH) {
      Span(frag.content).fontSize(15).fontColor(Theme.TextTertiary)
        .decoration({ type: TextDecorationType.LineThrough })
    } else if (frag.type === InlineFragmentType.INLINE_CODE) {
      Span(' ' + frag.content + ' ').fontSize(14).fontFamily('monospace')
        .fontColor('#BF5AF2').fontWeight(FontWeight.Medium)
    } else if (frag.type === InlineFragmentType.LINK) {
      Span(frag.content).fontSize(15).fontColor(Theme.AccentBlue)
        .decoration({ type: TextDecorationType.Underline })
    } else if (frag.type === InlineFragmentType.IMG) {
      Span('[图片:' + frag.content + ']').fontSize(13).fontColor(Theme.TextTertiary)
    } else if (frag.type === InlineFragmentType.COLOR_GREEN) {
      Span(frag.content).fontSize(15).fontColor(Theme.AccentGreen)
    } else if (frag.type === InlineFragmentType.COLOR_RED) {
      Span(frag.content).fontSize(15).fontColor(Theme.ErrorColor)
    } else {
      Span(frag.content).fontSize(15).fontColor(Theme.TextPrimary)
    }
  }

  // ── 无序列表（含任务列表、嵌套） ──

  @Builder
  UnorderedListView(node: MDNode) {
    Column() {
      ForEach(node.items, (item: string, itemIdx: number) => {
        Row({ space: 6 }) {
          this.ListBullet(node, itemIdx)
          this.InlineFormattedText(item)
        }
        .width('100%').margin({ bottom: 1 }).alignItems(VerticalAlign.Top)
      }, (item: string, itemIdx: number) => `ul-${itemIdx}`)
    }
    .width('100%').padding({ left: 4 }).margin({ top: 1, bottom: 1 })
  }

  @Builder
  ListBullet(node: MDNode, itemIdx: number) {
    if (node.listHelpers.length > itemIdx && node.listHelpers[itemIdx].checked >= 0) {
      if (node.listHelpers[itemIdx].checked === 1) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(14).fontColor([Theme.SuccessColor])
      } else {
        SymbolGlyph($r('sys.symbol.circle')).fontSize(14).fontColor([Theme.TextTertiary])
      }
    } else {
      Text('•').fontSize(15).fontColor(Theme.TextSecondary)
    }
  }

  // ── 有序列表 ──

  @Builder
  OrderedListView(node: MDNode) {
    Column() {
      ForEach(node.items, (item: string, itemIdx: number) => {
        Row({ space: 6 }) {
          Text((itemIdx + 1) + '.').fontSize(15).fontColor(Theme.TextSecondary).width(22).textAlign(TextAlign.End)
          this.InlineFormattedText(item)
        }
        .width('100%').margin({ bottom: 1 }).alignItems(VerticalAlign.Top)
      }, (item: string, itemIdx: number) => `ol-${itemIdx}`)
    }
    .width('100%').padding({ left: 4 }).margin({ top: 1, bottom: 1 })
  }

  // ── 引用 ──

  @Builder
  BlockquoteView(node: MDNode) {
    Row({ space: 6 }) {
      Column().width(3).height('100%').backgroundColor(Theme.TextSecondary).borderRadius(2)
      Text(node.text).fontSize(15).fontStyle(FontStyle.Italic).fontColor(Theme.TextSecondary).layoutWeight(1)
    }
    .width('100%').padding({ left: 8, right: 8 }).margin({ top: 3, bottom: 3 })
  }

  // ── 列表行内格式 ──

  @Builder
  InlineFormattedText(text: string) {
    Text() {
      ForEach(this.parseInline(text), (frag: InlineFragment, fi: number) => {
        this.renderInlineFragment(frag)
      }, (frag: InlineFragment, fi: number) => `ilf-${fi}`)
    }
    .lineHeight(20).layoutWeight(1)
  }
}

// ── 异步图片加载组件 ──

@Component
struct AsyncImage {
  private url: string = ''
  private resolver: (url: string) => Promise<string> = async (u) => u
  private alt: string = ''
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
        .height(80)
        .backgroundColor('rgba(255,255,255,0.05)')
        .borderRadius(8)

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
        .height(60)
        .backgroundColor('rgba(255,255,255,0.05)')
        .borderRadius(8)
        .onClick(() => { this.loadImage() })

      } else if (this.resolvedSrc) {
        Image(this.resolvedSrc)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .constraintSize({ maxHeight: 240 })
          .backgroundColor('rgba(0,0,0,0.1)')
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
