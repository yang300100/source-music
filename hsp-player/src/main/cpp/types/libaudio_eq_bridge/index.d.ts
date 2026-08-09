export interface AudioEqBridge {
  isSupported(): boolean
  initialize(): boolean
  release(): void
  setEnabled(enabled: boolean): boolean
  setGains(gains: number[]): boolean
  getGains(): number[]
  setPreset(presetName: string): boolean
  playerStart(url: string, positionMs?: number, autoPlay?: boolean): boolean
  playerStop(): void
  playerPause(): boolean
  playerResume(): boolean
  playerSeek(positionMs: number): boolean
  playerGetState(): number
  playerGetPosition(): number
  playerGetDuration(): number
  playerGetLastError(): string
}

declare const audioEqBridge: AudioEqBridge
export default audioEqBridge
