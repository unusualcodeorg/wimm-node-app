import { Module } from '@nestjs/common';
import { Content, ContentSchema } from './schemas/content.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { ContentController } from './content.controller';
import { ContentService } from './content.service';
import { ContentAdminController } from './content-admin.controller';
import { TopicModule } from '../topic/topic.module';
import { MentorModule } from '../mentor/mentor.module';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Content.name, schema: ContentSchema }]),
    TopicModule,
    MentorModule,
  ],
  controllers: [ContentController, ContentAdminController],
  providers: [ContentService],
  exports: [ContentService],
})
export class ContentModule {}
