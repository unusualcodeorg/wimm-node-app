import { Module } from '@nestjs/common';
import { Content, ContentSchema } from './schemas/content.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { ContentController } from './content.controller';
import { ContentService } from './content.service';
import { ContentAdminController } from './content-admin.controller';
import { TopicModule } from '../topic/topic.module';
import { MentorModule } from '../mentor/mentor.module';
import { ContentPrivateController } from './content-private.controller';
import { ContentsController } from './contents.controller';
import { ContentsService } from './contents.service';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Content.name, schema: ContentSchema }]),
    TopicModule,
    MentorModule,
  ],
  controllers: [
    ContentController,
    ContentAdminController,
    ContentPrivateController,
    ContentsController,
  ],
  providers: [ContentService, ContentsService],
  exports: [ContentService, ContentsService],
})
export class ContentModule {}
