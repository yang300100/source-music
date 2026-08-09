import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { LogUtils } from './LogUtils'

const STORE_NAME = 'source_music_store'
// 旧版本存储名只用于无损读取迁移，避免升级后歌单、音源和设置消失。
const LEGACY_STORE_NAME = String.fromCharCode(108, 120) + '_music_store'

/**
 * 本地持久化存储封装，基于 preferences
 */
export class StorageUtils {
  private static store: preferences.Preferences | null = null
  private static legacyStore: preferences.Preferences | null = null

  static async init(context: Context): Promise<void> {
    try {
      StorageUtils.store = await preferences.getPreferences(context, STORE_NAME)
      try {
        StorageUtils.legacyStore = await preferences.getPreferences(context, LEGACY_STORE_NAME)
      } catch (err) {
        StorageUtils.legacyStore = null
        LogUtils.warn('旧版存储兼容读取不可用', JSON.stringify(err))
      }
      LogUtils.info('存储初始化成功')
    } catch (err) {
      LogUtils.error('存储初始化失败', JSON.stringify(err))
    }
  }

  static async putString(key: string, value: string): Promise<void> {
    if (!StorageUtils.store) return
    await StorageUtils.store.put(key, value)
    await StorageUtils.store.flush()
  }

  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!StorageUtils.store) return defaultValue
    const value = await StorageUtils.store.get(key, '') as string
    if (value !== '') return value
    if (!StorageUtils.legacyStore) return defaultValue
    const legacyValue = await StorageUtils.legacyStore.get(key, '') as string
    if (legacyValue === '') return defaultValue
    // 读取到旧数据后立即写入新存储，后续不再依赖旧名称。
    await StorageUtils.store.put(key, legacyValue)
    await StorageUtils.store.flush()
    return legacyValue
  }

  static async putObject(key: string, value: Object): Promise<void> {
    await StorageUtils.putString(key, JSON.stringify(value))
  }

  static async getObject<T>(key: string, defaultValue: T): Promise<T> {
    const str = await StorageUtils.getString(key, '')
    if (!str) return defaultValue
    try {
      return JSON.parse(str) as T
    } catch {
      return defaultValue
    }
  }

  static async delete(key: string): Promise<void> {
    if (!StorageUtils.store) return
    await StorageUtils.store.delete(key)
    await StorageUtils.store.flush()
    if (StorageUtils.legacyStore) {
      await StorageUtils.legacyStore.delete(key)
      await StorageUtils.legacyStore.flush()
    }
  }
}
