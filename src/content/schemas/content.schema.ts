import { Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type ContentDocument = HydratedDocument<Content>;

export enum ContentCategory {
  AUDIO = 'AUDIO',
  VIDEO = 'VIDEO',
  IMAGE = 'IMAGE',
  YOUTUBE = 'YOUTUBE',
  ARTICLE = 'ARTICLE',
  QUOTE = 'QUOTE',
  MENTOR_INFO = 'MENTOR_INFO',
  TOPIC_INFO = 'TOPIC_INFO',
}

@Schema({ collection: 'contents', versionKey: false, timestamps: true })
export class Content {
  readonly _id: Types.ObjectId;
}

export const ContentSchema = SchemaFactory.createForClass(Content);
