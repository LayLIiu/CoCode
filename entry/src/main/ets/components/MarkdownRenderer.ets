/**
 * Markdown 渲染组件 - 与 iOS 端完全一致
 * 支持：标题、代码块(含复制)、行内代码、粗体、斜体、链接、列表、引用
 */

import { Theme } from '../common/Theme'
import pasteboard from '@ohos.pasteboard'

// 行内片段类型
enum InlineFragmentType {
  TEXT,
  BOLD,
  ITALIC,
  INLINE_CODE,
  LINK
}

class InlineFragment {
  type: InlineFragmentType = InlineFragmentType.TEXT
  content: string = ''
  url: string = '' // 仅 LINK 类型使用

  constructor(type: InlineFragmentType, content: string, url: string = '') {
    this.type = type
    this.content = content
    this.url = url
  }
}

// Markdown 节点类型
enum MDNodeType {
  CODE_BLOCK,
  HEADING,
  UNORDERED_LIST,
  ORDERED_LIST,
  BLOCKQUOTE,
  PARAGRAPH,
  SPACER
}

class MDNode {
  type: MDNodeType = MDNodeType.PARAGRAPH
  language: string = ''
  code: string = ''
  level: number = 1
  text: string = ''
  items: string[] = []
  fragments: InlineFragment[] = []

  static codeBlock(lang: string, code: string): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.CODE_BLOCK
    n.language = lang
    n.code = code
    return n
  }

  static heading(level: number, text: string): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.HEADING
    n.level = level
    n.text = text
    return n
  }

  static unorderedList(items: string[]): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.UNORDERED_LIST
    n.items = items
    return n
  }

  static orderedList(items: string[]): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.ORDERED_LIST
    n.items = items
    return n
  }

  static blockquote(text: string): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.BLOCKQUOTE
    n.text = text
    return n
  }

  static paragraph(fragments: InlineFragment[]): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.PARAGRAPH
    n.fragments = fragments
    return n
  }

  static spacer(): MDNode {
    const n = new MDNode()
    n.type = MDNodeType.SPACER
    return n
  }
}

@Component
export struct MarkdownRenderer {
  @Prop content: string = ''
  @State private nodes: MDNode[] = []

  aboutToAppear(): void {
    this.nodes = this.parseMarkdown(this.content)
  }

  // MARK: - 解析

  private parseMarkdown(text: string): MDNode[] {
    const nodes: MDNode[] = []
    const lines = text.split('\n')
    let i = 0

    while (i < lines.length) {
      const line = lines[i]

      // 代码块 ```
      if (line.trim().startsWith('```')) {
        const language = line.trim().substring(3).trim()
        const codeLines: string[] = []
        i++
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.push(lines[i])
          i++
        }
        nodes.push(MDNode.codeBlock(language, codeLines.join('\n')))
        i++ // 跳过结束 ```
        continue
      }

      // 标题 #
      if (line.startsWith('#')) {
        let level = 0
        let idx = 0
        while (idx < line.length && line[idx] === '#') {
          level++
          idx++
        }
        if (level >= 1 && level <= 6 && idx < line.length && line[idx] === ' ') {
          const text = line.substring(idx + 1).trim()
          nodes.push(MDNode.heading(level, text))
          i++
          continue
        }
      }

      // 引用 >
      const trimmed = line.trim()
      if (trimmed.startsWith('> ')) {
        nodes.push(MDNode.blockquote(trimmed.substring(2).trim()))
        i++
        continue
      }

      // 无序列表 - / * / +
      if (trimmed.match(/^[-*+]\s+/)) {
        const items: string[] = []
        while (i < lines.length && lines[i].trim().match(/^[-*+]\s+/)) {
          items.push(lines[i].trim().replace(/^[-*+]\s+/, ''))
          i++
        }
        nodes.push(MDNode.unorderedList(items))
        continue
      }

      // 有序列表
      if (trimmed.match(/^\d+\.\s+/)) {
        const items: string[] = []
        while (i < lines.length && lines[i].trim().match(/^\d+\.\s+/)) {
          items.push(lines[i].trim().replace(/^\d+\.\s+/, ''))
          i++
        }
        nodes.push(MDNode.orderedList(items))
        continue
      }

      // 空行
      if (trimmed === '') {
        nodes.push(MDNode.spacer())
        i++
        continue
      }

      // 普通段落
      nodes.push(MDNode.paragraph(this.parseInline(line)))
      i++
    }

    // 移除末尾空行
    while (nodes.length > 0 && nodes[nodes.length - 1].type === MDNodeType.SPACER) {
      nodes.pop()
    }

    return nodes
  }

  // 解析行内元素：`code` **bold** *italic* [text](url)
  private parseInline(text: string): InlineFragment[] {
    const fragments: InlineFragment[] = []
    let remaining = text

    while (remaining.length > 0) {
      // 行内代码 `code`
      const codeMatch = remaining.match(/`([^`]+)`/)
      if (codeMatch && codeMatch.index !== undefined && codeMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.INLINE_CODE, codeMatch[1]))
        remaining = remaining.substring(codeMatch[0].length)
        continue
      }

      // 粗体 **text**
      const boldMatch = remaining.match(/\*\*([^*]+)\*\*/)
      if (boldMatch && boldMatch.index !== undefined && boldMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.BOLD, boldMatch[1]))
        remaining = remaining.substring(boldMatch[0].length)
        continue
      }

      // 斜体 *text*
      const italicMatch = remaining.match(/\*([^*]+)\*/)
      if (italicMatch && italicMatch.index !== undefined && italicMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.ITALIC, italicMatch[1]))
        remaining = remaining.substring(italicMatch[0].length)
        continue
      }

      // 链接 [text](url)
      const linkMatch = remaining.match(/\[([^\]]+)\]\(([^)]+)\)/)
      if (linkMatch && linkMatch.index !== undefined && linkMatch.index === 0) {
        fragments.push(new InlineFragment(InlineFragmentType.LINK, linkMatch[1], linkMatch[2]))
        remaining = remaining.substring(linkMatch[0].length)
        continue
      }

      // 普通文本 - 找到下一个特殊字符
      const nextSpecial = this.findNextSpecial(remaining)
      if (nextSpecial > 0) {
        fragments.push(new InlineFragment(InlineFragmentType.TEXT, remaining.substring(0, nextSpecial)))
        remaining = remaining.substring(nextSpecial)
      } else if (nextSpecial === 0) {
        // 特殊字符开头但没匹配上，取一个字符
        fragments.push(new InlineFragment(InlineFragmentType.TEXT, remaining.charAt(0)))
        remaining = remaining.substring(1)
      } else {
        // 没找到特殊字符，取全部
        fragments.push(new InlineFragment(InlineFragmentType.TEXT, remaining))
        remaining = ''
      }
    }

    return fragments
  }

  private findNextSpecial(text: string): number {
    let pos = -1
    const chars = ['`', '*', '[']
    for (let i = 0; i < chars.length; i++) {
      const idx = text.indexOf(chars[i])
      if (idx >= 0 && (pos < 0 || idx < pos)) {
        pos = idx
      }
    }
    return pos
  }

  // MARK: - 构建

  build() {
    Column() {
      ForEach(this.nodes, (node: MDNode, index: number) => {
        if (node.type === MDNodeType.CODE_BLOCK) {
          this.CodeBlockView(node)
        } else if (node.type === MDNodeType.HEADING) {
          this.HeadingView(node)
        } else if (node.type === MDNodeType.UNORDERED_LIST) {
          this.UnorderedListView(node)
        } else if (node.type === MDNodeType.ORDERED_LIST) {
          this.OrderedListView(node)
        } else if (node.type === MDNodeType.BLOCKQUOTE) {
          this.BlockquoteView(node)
        } else if (node.type === MDNodeType.PARAGRAPH) {
          this.ParagraphView(node)
        } else if (node.type === MDNodeType.SPACER) {
          Row().height(4)
        }
      }, (node: MDNode, index: number) => `md-${index}`)
    }
    .width('100%')
  }

  // 代码块 - 与 iOS 一致：语言标签 + 复制按钮
  @Builder
  CodeBlockView(node: MDNode) {
    Column({ space: 0 }) {
      // Header
      Row() {
        Text(node.language ? node.language.toLowerCase() : 'code')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontFamily('monospace')
          .fontColor('#FFFFFF99')

        Blank()

        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(11)
          .fontColor(['#FFFFFF99'])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#1E1E1E')
      .onClick(() => {
        this.copyCode(node.code)
      })

      // 代码内容
      Scroll() {
        Text(node.code)
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor('#FFFFFFE6')
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .width('100%')
    .backgroundColor('#1A1A1A')
    .borderRadius(8)
    .margin({ top: 4, bottom: 4 })
    .clip(true)
  }

  private copyCode(code: string): void {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code)
      systemPasteboard.setData(pasteData)
    } catch (e) {
      console.error(`[MarkdownRenderer] pasteboard error: ${e}`)
    }
  }

  // 标题
  @Builder
  HeadingView(node: MDNode) {
    Text(node.text)
      .fontSize(24 - node.level * 2)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.TextPrimary)
      .width('100%')
      .margin({ top: node.level === 1 ? 8 : 4, bottom: 2 })
  }

  // 段落 - 带行内格式化
  @Builder
  ParagraphView(node: MDNode) {
    if (node.fragments.length === 0) {
      Text('')
    } else {
      Text() {
        ForEach(node.fragments, (frag: InlineFragment, fi: number) => {
          if (frag.type === InlineFragmentType.BOLD) {
            Span(frag.content)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextPrimary)
          } else if (frag.type === InlineFragmentType.ITALIC) {
            Span(frag.content)
              .fontSize(15)
              .fontStyle(FontStyle.Italic)
              .fontColor(Theme.TextPrimary)
          } else if (frag.type === InlineFragmentType.INLINE_CODE) {
            Span(' ' + frag.content + ' ')
              .fontSize(14)
              .fontFamily('monospace')
              .fontColor('#BF5AF2')
              .fontWeight(FontWeight.Medium)
          } else if (frag.type === InlineFragmentType.LINK) {
            Span(frag.content)
              .fontSize(15)
              .fontColor(Theme.AccentBlue)
              .decoration({ type: TextDecorationType.Underline })
          } else {
            Span(frag.content)
              .fontSize(15)
              .fontColor(Theme.TextPrimary)
          }
        }, (frag: InlineFragment, fi: number) => `frag-${fi}`)
      }
      .lineHeight(22)
      .width('100%')
    }
  }

  // 无序列表
  @Builder
  UnorderedListView(node: MDNode) {
    Column() {
      ForEach(node.items, (item: string, itemIdx: number) => {
        Row({ space: 8 }) {
          Text('•')
            .fontSize(15)
            .fontColor(Theme.TextSecondary)
            .width(16)

          this.InlineFormattedText(item)
        }
        .width('100%')
        .margin({ bottom: 2 })
        .alignItems(VerticalAlign.Top)
      }, (item: string, itemIdx: number) => `ul-${itemIdx}`)
    }
    .width('100%')
    .padding({ left: 8 })
    .margin({ top: 2, bottom: 2 })
  }

  // 有序列表
  @Builder
  OrderedListView(node: MDNode) {
    Column() {
      ForEach(node.items, (item: string, itemIdx: number) => {
        Row({ space: 8 }) {
          Text(`${itemIdx + 1}.`)
            .fontSize(15)
            .fontColor(Theme.TextSecondary)
            .width(24)
            .textAlign(TextAlign.End)

          this.InlineFormattedText(item)
        }
        .width('100%')
        .margin({ bottom: 2 })
        .alignItems(VerticalAlign.Top)
      }, (item: string, itemIdx: number) => `ol-${itemIdx}`)
    }
    .width('100%')
    .padding({ left: 8 })
    .margin({ top: 2, bottom: 2 })
  }

  // 引用块
  @Builder
  BlockquoteView(node: MDNode) {
    Row({ space: 8 }) {
      Column()
        .width(3)
        .height('100%')
        .backgroundColor('#FFFFFF4D')
        .borderRadius(2)

      Text(node.text)
        .fontSize(15)
        .fontStyle(FontStyle.Italic)
        .fontColor(Theme.TextSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 4 })
    .margin({ top: 4, bottom: 4 })
  }

  // 行内格式化文本（用于列表项）
  @Builder
  InlineFormattedText(text: string) {
    Text() {
      ForEach(this.parseInline(text), (frag: InlineFragment, fi: number) => {
        if (frag.type === InlineFragmentType.BOLD) {
          Span(frag.content).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TextPrimary)
        } else if (frag.type === InlineFragmentType.ITALIC) {
          Span(frag.content).fontSize(15).fontStyle(FontStyle.Italic).fontColor(Theme.TextPrimary)
        } else if (frag.type === InlineFragmentType.INLINE_CODE) {
          Span(frag.content)
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor('#BF5AF2')
        } else if (frag.type === InlineFragmentType.LINK) {
          Span(frag.content)
            .fontSize(15)
            .fontColor(Theme.AccentBlue)
            .decoration({ type: TextDecorationType.Underline })
        } else {
          Span(frag.content).fontSize(15).fontColor(Theme.TextPrimary)
        }
      }, (frag: InlineFragment, fi: number) => `ilf-${fi}`)
    }
    .lineHeight(22)
    .layoutWeight(1)
  }
}
