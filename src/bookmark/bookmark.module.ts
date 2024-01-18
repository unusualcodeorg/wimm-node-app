import { Module, forwardRef } from '@nestjs/common';
import { Bookmark, BookmarkSchema } from './schemas/bookmark.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { BookmarkController } from './bookmark.controller';
import { BookmarkService } from './bookmark.service';
import { ContentModule } from '../content/content.module';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: Bookmark.name, schema: BookmarkSchema },
    ]),
    forwardRef(() => ContentModule),
  ],
  controllers: [BookmarkController],
  providers: [BookmarkService],
  exports: [BookmarkService],
})
export class BookmarkModule {}
