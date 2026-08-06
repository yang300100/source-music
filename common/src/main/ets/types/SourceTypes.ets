import { MusicItem, SearchResult, LyricLine, PlaylistInfo, MusicQuality, SourceType } from './MusicTypes'

/**
 * 音源基本信息
 */
export interface SourceInfo {
  id: string
  name: string
  version: string
  author: string
  description: string
  type: SourceType
  scriptUrl?: string
  nativeModule?: string
}

/**
 * 可用音源实例接口
 */
export interface SourceInstance {
  info: SourceInfo
  enabled: boolean
  priority: number
  isNative: boolean

  search(query: string, page: number, quality: MusicQuality): Promise<SearchResult>
  getMusicInfo(songmid: string, quality: MusicQuality): Promise<MusicItem>
  getLyric(songmid: string): Promise<LyricLine[]>
  getPlaylistInfo(listid: string): Promise<PlaylistInfo>
  getHotSearch(): Promise<Array<{ label: string; value: string }>>
}

/**
 * 音源导入方式
 */
export enum SourceImportMethod {
  LOCAL_FILE = 'localFile',
  ONLINE_URL = 'onlineUrl',
  NATIVE_PACKAGE = 'nativePackage'
}

/**
 * 音源导入结果
 */
export interface SourceImportResult {
  success: boolean
  source?: SourceInstance
  error?: string
}
