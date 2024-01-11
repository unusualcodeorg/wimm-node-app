import { Module } from '@nestjs/common';
import { Topic, TopicSchema } from './schemas/topic.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { TopicController } from './topic.controller';
import { TopicService } from './topic.service';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Topic.name, schema: TopicSchema }]),
  ],
  controllers: [TopicController],
  providers: [TopicService],
})
export class TopicModule {}
