import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';
import { Content } from '../../content/schemas/content.schema';

export type BookmarkDocument = HydratedDocument<Bookmark>;

@Schema({ collection: 'bookmarks', versionKey: false, timestamps: true })
export class Bookmark {
  readonly _id: Types.ObjectId;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: User.name,
    required: true,
  })
  user: User;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: Content.name,
    required: true,
  })
  content: Content;

  @Prop({ default: true })
  status: boolean;
}

export const BookmarkSchema = SchemaFactory.createForClass(Bookmark);

BookmarkSchema.index({ user: 1, status: 1 });
BookmarkSchema.index({ content: 1, status: 1 });
BookmarkSchema.index({ user: 1, content: 1, status: 1 });
