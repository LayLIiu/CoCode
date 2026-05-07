/**
 * 常量定义
 */
export class Constants {
  // Tab标签名称
  static readonly TAB_CLAUDE: string = 'Claude'
  static readonly TAB_CODEX: string = 'CodeX'
  static readonly TAB_OPEN_CODE: string = 'Open Code'
  static readonly TAB_SETTINGS: string = '设置'
  
  // 页面标题
  static readonly TITLE_CLAUDE: string = 'Claude Code'
  static readonly TITLE_CODEX: string = 'CodeX'
  static readonly TITLE_OPEN_CODE: string = 'Open Code'
}

/**
 * Tab索引枚举
 */
export enum TabIndex {
  CLAUDE = 0,
  CODEX = 1,
  OPEN_CODE = 2,
  SETTINGS = 3
}
