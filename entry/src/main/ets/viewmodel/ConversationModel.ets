/**
 * 会话状态枚举
 */
export enum ConversationStatus {
  SLEEPING = 'sleeping',
  ACTIVE = 'active',
  ARCHIVED = 'archived'
}

/**
 * 图标颜色主题
 */
export enum IconTheme {
  BLUE = '#0A84FF',
  PURPLE = '#BF5AF2',
  ORANGE = '#FF9F0A',
  GREEN = '#30D158'
}

/**
 * 会话数据模型
 */
export interface ConversationModel {
  id: string
  title: string
  filePath: string
  messageCount: number
  timestamp: Date  // 改为Date类型
  status: ConversationStatus
  iconTheme: IconTheme
  tabType: TabType
}

/**
 * Tab类型
 */
export enum TabType {
  CLAUDE = 'Claude'
}

/**
 * 分组类型
 */
export enum DateGroup {
  TODAY = '今天',
  YESTERDAY = '昨天',
  LAST_SEVEN_DAYS = '最近七天',
  EARLIER = '更早'
}
