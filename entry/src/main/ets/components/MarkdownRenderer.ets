/**
 * Markdown 渲染组件
 * 与 iOS 端保持一致的实现
 */

import { Theme } from '../common/Theme'

// 节点类型
class MarkdownNode {
  type: string = ''
  content: string = ''
  language: string = ''
  level: number = 0
  items: string[] = []
  inlineElements: InlineElement[] = []
}

// 行内元素类型
class InlineElement {
  type: string = ''
  content: string = ''
  url: string = ''
}

@Component
export struct MarkdownRenderer {
  @Prop content: string = ''
  @State private parsedNodes: MarkdownNode[] = []

  aboutToAppear(): void {
    // 直接解析，不做缓存（避免 ArkTS 类型限制问题）
    this.parsedNodes = this.parseMarkdown(this.content)
  }

  // 解析 Markdown 内容
  private parseMarkdown(text: string): MarkdownNode[] {
    const nodes: MarkdownNode[] = []
    const lines = text.split('\n')
    let i = 0

    while (i < lines.length) {
      const line = lines[i]

      // 代码块
      if (line.trim().startsWith('```')) {
        const language = line.trim().substring(3).trim()
        const codeLines: string[] = []
        i++

        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.push(lines[i])
          i++
        }

        const node = new MarkdownNode()
        node.type = 'code'
        node.content = codeLines.join('\n')
        node.language = language
        nodes.push(node)
        i++
        continue
      }

      // 标题
      if (line.startsWith('#')) {
        const match = line.match(/^(#{1,6})\s+(.*)/)
        if (match && match.length >= 3) {
          const node = new MarkdownNode()
          node.type = 'heading'
          node.level = match[1].length
          node.content = match[2]
          nodes.push(node)
          i++
          continue
        }
      }

      // 无序列表
      if (line.trim().match(/^[-*+]\s+/)) {
        const items: string[] = []
        while (i < lines.length && lines[i].trim().match(/^[-*+]\s+/)) {
          items.push(lines[i].trim().replace(/^[-*+]\s+/, ''))
          i++
        }
        const node = new MarkdownNode()
        node.type = 'list'
        node.items = items
        nodes.push(node)
        continue
      }

      // 有序列表
      if (line.trim().match(/^\d+\.\s+/)) {
        const items: string[] = []
        while (i < lines.length && lines[i].trim().match(/^\d+\.\s+/)) {
          items.push(lines[i].trim().replace(/^\d+\.\s+/, ''))
          i++
        }
        const node = new MarkdownNode()
        node.type = 'numbered-list'
        node.items = items
        nodes.push(node)
        continue
      }

      // 引用块
      if (line.trim().startsWith('>')) {
        const quoteLines: string[] = []
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.push(lines[i].trim().replace(/^>\s?/, ''))
          i++
        }
        const node = new MarkdownNode()
        node.type = 'blockquote'
        node.content = quoteLines.join('\n')
        nodes.push(node)
        continue
      }

      // 空行
      if (line.trim() === '') {
        const node = new MarkdownNode()
        node.type = 'newline'
        nodes.push(node)
        i++
        continue
      }

      // 普通段落
      if (line.trim()) {
        const node = new MarkdownNode()
        node.type = 'paragraph'
        node.inlineElements = this.parseInlineElements(line)
        nodes.push(node)
      }

      i++
    }

    // 移除末尾空行
    while (nodes.length > 0 && nodes[nodes.length - 1].type === 'newline') {
      nodes.pop()
    }

    return nodes
  }

  // 解析行内元素
  private parseInlineElements(text: string): InlineElement[] {
    const elements: InlineElement[] = []
    let remaining = text

    while (remaining.length > 0) {
      // 链接 [text](url)
      const linkMatch = remaining.match(/\[([^\]]+)\]\(([^)]+)\)/)
      if (linkMatch && linkMatch.index === 0) {
        const el = new InlineElement()
        el.type = 'link'
        el.content = linkMatch[1]
        el.url = linkMatch[2]
        elements.push(el)
        remaining = remaining.substring(linkMatch[0].length)
        continue
      }

      // 粗体 **text**
      const boldMatch = remaining.match(/\*\*([^*]+)\*\*/)
      if (boldMatch && boldMatch.index === 0) {
        const el = new InlineElement()
        el.type = 'bold'
        el.content = boldMatch[1]
        elements.push(el)
        remaining = remaining.substring(boldMatch[0].length)
        continue
      }

      // 斜体 *text*
      const italicMatch = remaining.match(/\*([^*]+)\*/)
      if (italicMatch && italicMatch.index === 0) {
        const el = new InlineElement()
        el.type = 'italic'
        el.content = italicMatch[1]
        elements.push(el)
        remaining = remaining.substring(italicMatch[0].length)
        continue
      }

      // 行内代码 `text`
      const codeMatch = remaining.match(/`([^`]+)`/)
      if (codeMatch && codeMatch.index === 0) {
        const el = new InlineElement()
        el.type = 'inline-code'
        el.content = codeMatch[1]
        elements.push(el)
        remaining = remaining.substring(codeMatch[0].length)
        continue
      }

      // 普通文本
      const el = new InlineElement()
      el.type = 'text'
      el.content = remaining.charAt(0)
      elements.push(el)
      remaining = remaining.substring(1)
    }

    return elements
  }

  // 获取行内元素文本
  private getInlineText(elements: InlineElement[]): string {
    let result = ''
    for (let i = 0; i < elements.length; i++) {
      result += elements[i].content
    }
    return result
  }

  build() {
    Column() {
      ForEach(this.parsedNodes, (node: MarkdownNode, index: number) => {
        if (node.type === 'code') {
          this.CodeBlock(node)
        } else if (node.type === 'heading') {
          this.Heading(node)
        } else if (node.type === 'paragraph') {
          this.Paragraph(node)
        } else if (node.type === 'list') {
          this.List(node)
        } else if (node.type === 'numbered-list') {
          this.NumberedList(node)
        } else if (node.type === 'blockquote') {
          this.Blockquote(node)
        } else if (node.type === 'newline') {
          Row().height(4)
        }
      }, (node: MarkdownNode, index: number) => `node-${index}`)
    }
    .width('100%')
  }

  @Builder
  CodeBlock(node: MarkdownNode) {
    Column() {
      Row() {
        Text(node.language || 'code')
          .fontSize(12)
          .fontColor('#888888')
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16)
          .fontColor(['#888888'])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Text(node.content)
          .fontSize(13)
          .fontColor('#d4d4d4')
          .fontFamily('monospace')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .backgroundColor('#1e1e1e')
    .borderRadius(8)
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  Heading(node: MarkdownNode) {
    Text(node.content)
      .fontSize(24 - node.level * 2)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.TextPrimary)
      .width('100%')
      .margin({ top: node.level === 1 ? 16 : 12, bottom: 4 })
  }

  @Builder
  Paragraph(node: MarkdownNode) {
    Text(this.getInlineText(node.inlineElements))
      .fontSize(15)
      .fontColor(Theme.TextPrimary)
      .lineHeight(22)
      .width('100%')
  }

  @Builder
  List(node: MarkdownNode) {
    Column() {
      ForEach(node.items, (item: string, itemIndex: number) => {
        Row() {
          Text('•')
            .fontSize(15)
            .fontColor(Theme.TextSecondary)
            .width(20)

          Text(item)
            .fontSize(15)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 2 })
      }, (item: string, itemIndex: number) => `item-${itemIndex}`)
    }
    .width('100%')
    .padding({ left: 16 })
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  NumberedList(node: MarkdownNode) {
    Column() {
      ForEach(node.items, (item: string, itemIndex: number) => {
        Row() {
          Text(`${itemIndex + 1}.`)
            .fontSize(15)
            .fontColor(Theme.TextSecondary)
            .width(20)

          Text(item)
            .fontSize(15)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 2 })
      }, (item: string, itemIndex: number) => `num-item-${itemIndex}`)
    }
    .width('100%')
    .padding({ left: 16 })
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  Blockquote(node: MarkdownNode) {
    Row() {
      Column() {
        Text(node.content)
          .fontSize(15)
          .fontColor(Theme.TextSecondary)
          .fontStyle(FontStyle.Italic)
      }
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(4)
    .border({ width: { left: 4 }, color: Theme.Border })
    .backgroundColor(Theme.BackgroundSecondary)
    .margin({ top: 4, bottom: 4 })
  }
}
