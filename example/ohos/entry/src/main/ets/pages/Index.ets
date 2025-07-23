import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import window from '@ohos.window';

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";

  aboutToAppear(): void {
    let windowStage = AppStorage.get("windowStage") as window.WindowStage;
    AppStorage.setOrCreate("context", windowStage.getMainWindowSync().getUIContext());
  }

  build() {
    Column() {
      FlutterPage({ viewId: this.viewId })
    }
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}