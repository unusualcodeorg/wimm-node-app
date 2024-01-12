import { Module } from '@nestjs/common';
import { Topic, TopicSchema } from './schemas/topic.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { TopicController } from './topic.controller';
import { TopicService } from './topic.service';
import { TopicAdminController } from './topic-admin.controller';
import { TopicsController } from './topics.controller';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Topic.name, schema: TopicSchema }]),
  ],
  controllers: [TopicController, TopicAdminController, TopicsController],
  providers: [TopicService],
  exports: [TopicService],
})
export class TopicModule {}
