import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';
import { Topic } from '../../topic/schemas/topic.schema';
import { Mentor } from '../../mentor/schemas/mentor.schema';

export enum Category {
  AUDIO = 'AUDIO',
  VIDEO = 'VIDEO',
  IMAGE = 'IMAGE',
  YOUTUBE = 'YOUTUBE',
  ARTICLE = 'ARTICLE',
  QUOTE = 'QUOTE',
  MENTOR_INFO = 'MENTOR_INFO',
  TOPIC_INFO = 'TOPIC_INFO',
}

export type ContentDocument = HydratedDocument<Content>;

@Schema({ collection: 'contents', versionKey: false, timestamps: true })
export class Content {
  readonly _id: Types.ObjectId;

  @Prop({ required: true, enum: Object.values(Category) })
  category: Category;

  @Prop({ required: true, maxlength: 500, trim: true })
  title: string;

  @Prop({ required: true, maxlength: 100, trim: true })
  subtitle: string;

  @Prop({ required: false, select: false, maxlength: 2000, trim: true })
  description?: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  thumbnail: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  extra: string;

  @Prop({
    type: [{ type: mongoose.Schema.Types.ObjectId, ref: Topic.name }],
  })
  topics: Topic[];

  @Prop({
    type: [{ type: mongoose.Schema.Types.ObjectId, ref: Mentor.name }],
  })
  mentors: Mentor[];

  @Prop({
    type: [
      { type: mongoose.Schema.Types.ObjectId, ref: User.name, select: false },
    ],
  })
  likedBy?: User[];

  @Prop({ default: 0, min: 0 })
  likes: number;

  @Prop({ default: 0, min: 0 })
  views: number;

  @Prop({ default: 0, min: 0 })
  shares: number;

  @Prop({ default: false })
  general: boolean;

  @Prop({ default: 0.01, max: 1, min: 0 })
  score: number;

  @Prop({ default: true })
  private: boolean;

  @Prop({ default: false, select: false })
  submit?: boolean;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: User.name,
    required: true,
  })
  createdBy: User;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: User.name,
    required: true,
    select: false,
  })
  updatedBy?: User;

  @Prop({ default: true })
  status: boolean;
}

export const ContentSchema = SchemaFactory.createForClass(Content);

ContentSchema.index(
  { title: 'text', subtitle: 'text' },
  { weights: { title: 3, subtitle: 1 }, background: false },
);

ContentSchema.index({ _id: 1, status: 1 });
ContentSchema.index({ createdBy: 1, status: 1 });
