import { MainPage } from './MainPage'

@Entry
@Component
struct Index {
  build() {
    Column() {
      MainPage()
    }
    .width('100%')
    .height('100%')
  }
}
