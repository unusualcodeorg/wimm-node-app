import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';

export type TopicDocument = HydratedDocument<Topic>;

@Schema({ collection: 'topics', versionKey: false, timestamps: true })
export class Topic {
  readonly _id: Types.ObjectId;

  @Prop({ required: true, maxlength: 50, trim: true })
  name: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  title: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  thumbnail: string;

  @Prop({ required: true, maxlength: 10000, trim: true })
  description: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  coverImgUrl: string;

  @Prop({ default: 0.01, max: 1, min: 0 })
  score: number;

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
  })
  updatedBy: User;

  @Prop({ default: true })
  status: boolean;
}

export const TopicSchema = SchemaFactory.createForClass(Topic);

TopicSchema.index(
  { name: 'text', title: 'text' },
  { weights: { name: 3, title: 1 }, background: false },
);

TopicSchema.index({ _id: 1, status: 1 });
