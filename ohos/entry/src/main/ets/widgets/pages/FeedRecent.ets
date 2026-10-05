import { FeedSummaryCard } from '../components/FeedSummaryCard';

const storage = new LocalStorage();

@Entry(storage)
@Component
struct FeedRecent {
  build() {
    Column() {
      FeedSummaryCard({ dimension: 2 })
    }.width('100%').height('100%')
  }
}
