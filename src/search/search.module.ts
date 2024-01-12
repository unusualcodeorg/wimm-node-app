import { Module } from '@nestjs/common';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';
import { MentorModule } from '../mentor/mentor.module';
import { TopicModule } from '../topic/topic.module';
import { ContentModule } from '../content/content.module';

@Module({
  imports: [MentorModule, TopicModule, ContentModule],
  controllers: [SearchController],
  providers: [SearchService],
  exports: [SearchService],
})
export class SearchModule {}
