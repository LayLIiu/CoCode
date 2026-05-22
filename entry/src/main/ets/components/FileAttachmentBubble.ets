/**
 * 文件附件气泡 — 显示文件卡片
 * 支持图片预览、代码内容、文件下载等
 */

import { Theme } from '../common/Theme'
import { fileService } from '../services/FileService'
import { downloadService } from '../services/DownloadService'

function getFileTypeIconResource(ext: string): Resource {
  const imgExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic']
  const codeExts = ['ts', 'tsx', 'js', 'jsx', 'py', 'rs', 'go', 'java', 'kt',
    'swift', 'css', 'html', 'json', 'xml', 'yaml', 'yml', 'md', 'sh', 'c', 'cpp']
  const archiveExts = ['zip', 'tar', 'gz', 'rar', '7z']
  const audioExts = ['mp3', 'wav', 'ogg', 'aac', 'm4a', 'wma', 'flac', 'opus']
  const docExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx']

  if (imgExts.indexOf(ext) >= 0) return $r('sys.symbol.arrow_down_circle')
  if (codeExts.indexOf(ext) >= 0) return $r('sys.symbol.chevron_forward')
  if (archiveExts.indexOf(ext) >= 0) return $r('sys.symbol.folder')
  if (audioExts.indexOf(ext) >= 0) return $r('sys.symbol.mic')
  if (docExts.indexOf(ext) >= 0) return $r('sys.symbol.doc_text')
  if (['txt', 'log', 'cfg', 'ini', 'env'].indexOf(ext) >= 0) return $r('sys.symbol.doc_text')
  return $r('sys.symbol.doc_text')
}

function getFileTypeColor(ext: string): string {
  const imgExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic']
  const codeExts = ['ts', 'tsx', 'js', 'jsx', 'py', 'rs', 'go', 'java', 'kt',
    'swift', 'css', 'html', 'json', 'xml', 'yaml', 'yml', 'md', 'sh', 'c', 'cpp']
  const archiveExts = ['zip', 'tar', 'gz', 'rar', '7z']
  const audioExts = ['mp3', 'wav', 'ogg', 'aac', 'm4a', 'wma', 'flac', 'opus']
  const docExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx']

  if (imgExts.indexOf(ext) >= 0) return '#30D158'
  if (codeExts.indexOf(ext) >= 0) return '#0A84FF'
  if (archiveExts.indexOf(ext) >= 0) return '#FF9F0A'
  if (audioExts.indexOf(ext) >= 0) return '#BF5AF2'
  if (docExts.indexOf(ext) >= 0) return '#FF3B30'
  if (['txt', 'log', 'cfg', 'ini', 'env'].indexOf(ext) >= 0) return '#8E8E93'
  return '#636366'
}

@Component
export struct FileAttachmentBubble {
  @Prop @Watch('onFilePathChanged') filePath: string = ''
  @State fileName: string = ''
  @State fileExt: string = ''
  @State fileIsImage: boolean = false
  @State fileIsSvg: boolean = false
  @State fileIsCode: boolean = false
  @State fileSizeLabel: string = ''
  @State thumbnailSrc: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State contentPreview: string = ''
  @State isDownloading: boolean = false
  @State downloadResult: string = ''

  private onImageTap?: (src: string, alt: string, name: string) => void

  aboutToAppear(): void {
    this.analyzeFile()
  }

  private onFilePathChanged(): void {
    this.analyzeFile()
  }

  private analyzeFile(): void {
    if (!this.filePath) return
    const info = fileService.analyzeFilePath(this.filePath)
    this.fileName = info.name
    this.fileExt = info.ext
    this.fileIsImage = info.isImage
    this.fileIsSvg = info.isSvg
    this.fileIsCode = info.isCode
    this.fileSizeLabel = info.sizeLabel

    if (this.fileIsImage && !this.thumbnailSrc) {
      this.loadThumbnail()
    }
  }

  private async loadThumbnail(): Promise<void> {
    if (!this.filePath || this.thumbnailSrc) return
    this.isLoading = true
    try {
      const src = await fileService.fetchImageBase64(this.filePath)
      if (src) {
        this.thumbnailSrc = src
      } else {
        this.errorMessage = '加载失败'
      }
    } catch (e) {
      this.errorMessage = '加载失败'
    }
    this.isLoading = false
  }

  build() {
    Column({ space: 0 }) {
      if (this.fileIsImage && this.thumbnailSrc) {
        this.ImagePreviewCard()
      } else if (this.fileIsSvg) {
        this.SvgPreviewCard()
      } else if (this.fileIsCode) {
        this.CodeFileCard()
      } else {
        this.GenericFileCard()
      }
    }
    .width('100%')
  }

  @Builder
  ImagePreviewCard() {
    Column({ space: 6 }) {
      Image(this.thumbnailSrc)
        .width('100%')
        .objectFit(ImageFit.Contain)
        .borderRadius({ topLeft: 10, topRight: 10 })
        .constraintSize({ maxHeight: 240 })
        .backgroundColor('rgba(0,0,0,0.15)')

      Row({ space: 6 }) {
        Text('🖼')
          .fontSize(12)

        Text(this.fileName)
          .fontSize(11)
          .fontColor(Theme.TextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.fileSizeLabel) {
          Text(this.fileSizeLabel)
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }

        Text('⛶')
          .fontSize(12)
          .fontColor(Theme.AccentBlue)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(10)
    .onClick(() => {
      if (this.onImageTap) {
        this.onImageTap(this.thumbnailSrc, this.fileName, this.fileName)
      }
    })
  }

  @Builder
  SvgPreviewCard() {
    Column({ space: 6 }) {
      if (this.thumbnailSrc) {
        Image(this.thumbnailSrc)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius({ topLeft: 10, topRight: 10 })
          .constraintSize({ maxHeight: 240 })
          .backgroundColor('rgba(0,0,0,0.1)')
      } else {
        Column() {
          Text('🖼')
            .fontSize(32)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(255,255,255,0.05)')
        .borderRadius({ topLeft: 10, topRight: 10 })
      }

      Row({ space: 6 }) {
        Text('SVG ' + this.fileName)
          .fontSize(11).fontColor(Theme.TextSecondary).layoutWeight(1)
      }
      .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(10)
  }

  @Builder
  CodeFileCard() {
    Row({ space: 12 }) {
      Text('⟩')
        .fontSize(24)
        .fontColor('#0A84FF')

      Column({ space: 4 }) {
        Text(this.fileName).fontSize(14).fontColor(Theme.TextPrimary).maxLines(1)
        if (this.fileSizeLabel) {
          Text(this.fileSizeLabel).fontSize(11).fontColor(Theme.TextTertiary)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('.' + this.fileExt.toUpperCase())
        .fontSize(10).fontWeight(FontWeight.Bold)
        .fontColor('#0A84FF')
        .backgroundColor('rgba(10,132,255,0.15)')
        .borderRadius(4)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor('rgba(255,255,255,0.06)')
    .borderRadius(10)
    .onClick(() => {
      this.loadAndPreviewContent()
    })
  }

  @Builder
  GenericFileCard() {
    Row({ space: 12 }) {
      SymbolGlyph(getFileTypeIconResource(this.fileExt))
        .fontSize(24)
        .fontColor([getFileTypeColor(this.fileExt)])

      Column({ space: 4 }) {
        Text(this.fileName).fontSize(14).fontColor(Theme.TextPrimary).maxLines(1)
        if (this.fileSizeLabel) {
          Text(this.fileSizeLabel).fontSize(11).fontColor(Theme.TextTertiary)
        }
        if (this.downloadResult) {
          Text(this.downloadResult).fontSize(10).fontColor(Theme.TextTertiary)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isDownloading) {
        LoadingProgress().width(16).height(16)
      } else {
        Text('↓')
          .fontSize(16)
          .fontColor(Theme.AccentBlue)
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('rgba(255,255,255,0.06)')
    .borderRadius(10)
    .onClick(() => {
      this.downloadFile()
    })
  }

  private async downloadFile(): Promise<void> {
    if (this.isDownloading || !this.filePath) return
    this.isDownloading = true
    this.downloadResult = ''

    try {
      const path = await downloadService.downloadToSandbox(
        this.filePath,
        this.fileName || 'file'
      )
      this.downloadResult = '已保存'
      setTimeout(() => { this.downloadResult = '' }, 3000)
    } catch (e) {
      console.error('[FileAttachment] Download error: ' + e)
      this.downloadResult = '下载失败'
      setTimeout(() => { this.downloadResult = '' }, 3000)
    }

    this.isDownloading = false
  }

  private async loadAndPreviewContent(): Promise<void> {
    if (this.contentPreview) return
    this.isLoading = true
    try {
      const content = await fileService.fetchTextContent(this.filePath)
      if (content) {
        this.contentPreview = content.length > 3000 ?
          content.substring(0, 3000) + '\n\n... (内容已截断)' : content
      } else {
        this.errorMessage = '无法读取文件内容'
      }
    } catch (e) {
      this.errorMessage = '读取失败'
    }
    this.isLoading = false
  }
}