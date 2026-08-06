/**
 * 音源标识（与 lx-music 社区约定一致）
 * kg=酷狗, kw=酷我, tx=QQ, wy=网易, mg=咪咕, local=本地
 */
export enum SourceType {
  KG = 'kg',
  KW = 'kw',
  TX = 'tx',
  WY = 'wy',
  MG = 'mg',
  LOCAL = 'local',
  CUSTOM = 'custom'
}

/**
 * 音质级别
 */
export enum MusicQuality {
  LOW = '128k',
  HIGH = '320k',
  LOSSLESS = 'flac',
  HIRES = 'flac24bit'
}

/**
 * 某音质下的播放信息
 */
export interface MusicQualityInfo {
  url: string
  size: number
  br: number
}

/**
 * 一首歌包含的所有信息
 */
export interface MusicItem {
  songmid: string
  name: string
  singer: string
  albumName: string
  interval: number
  imgUrl: string
  lyricUrl: string
  source: SourceType
  types: Record<string, MusicQualityInfo>
  _types?: Record<string, MusicQualityInfo>
}

/**
 * 搜索结果
 */
export interface SearchResult {
  list: MusicItem[]
  total: number
  limit: number
  page: number
  source: SourceType
}

/**
 * 歌词行
 */
export interface LyricLine {
  time: number
  text: string
  transText?: string
}

/**
 * 歌单信息（来自音源）
 */
export interface PlaylistInfo {
  id: string
  name: string
  description: string
  coverUrl: string
  songCount: number
  source: SourceType
  songs: MusicItem[]
}

/**
 * 本地歌单（用户创建）
 */
export interface LocalPlaylist {
  id: string
  name: string
  description: string
  songs: MusicItem[]
  createdAt: number
  updatedAt: number
}

/**
 * 播放模式
 */
export enum PlayMode {
  SEQUENCE = 'sequence',
  LOOP_ONE = 'loopOne',
  LOOP_ALL = 'loopAll',
  SHUFFLE = 'shuffle'
}

/**
 * 热搜条目
 */
export interface HotSearchItem {
  label: string
  value: string
}

/**
 * 播放器状态
 */
export enum PlayerStatus {
  IDLE = 'idle',
  LOADING = 'loading',
  BUFFERING = 'buffering',
  PLAYING = 'playing',
  PAUSED = 'paused',
  ERROR = 'error'
}
