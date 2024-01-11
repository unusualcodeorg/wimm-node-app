import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';

export type MentorDocument = HydratedDocument<Mentor>;

@Schema({ collection: 'mentors', versionKey: false, timestamps: true })
export class Mentor {
  readonly _id: Types.ObjectId;

  @Prop({ required: true, maxlength: 50, trim: true })
  name: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  title: string;

  @Prop({ required: true, maxlength: 300, trim: true })
  thumbnail: string;

  @Prop({ required: true, maxlength: 50, trim: true })
  occupation: string;

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

export const MentorSchema = SchemaFactory.createForClass(Mentor);

MentorSchema.index(
  { name: 'text', occupation: 'text', title: 'text' },
  { weights: { name: 5, occupation: 1, title: 2 }, background: false },
);

MentorSchema.index({ _id: 1, status: 1 });
