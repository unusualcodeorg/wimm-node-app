import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';
import { Topic } from '../../topic/schemas/topic.schema';
import { Mentor } from '../../mentor/schemas/mentor.schema';

export type SubscriptionDocument = HydratedDocument<Subscription>;

@Schema({ collection: 'subscriptions', versionKey: false, timestamps: true })
export class Subscription {
  readonly _id: Types.ObjectId;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: User.name,
    required: true,
    unique: true,
    index: true,
  })
  user: User;

  @Prop({ type: [{ type: mongoose.Schema.Types.ObjectId, ref: Topic.name }] })
  topics: Topic[];

  @Prop({ type: [{ type: mongoose.Schema.Types.ObjectId, ref: Mentor.name }] })
  mentors: Mentor[];

  @Prop({ default: true })
  status: boolean;
}

export const SubscriptionSchema = SchemaFactory.createForClass(Subscription);

SubscriptionSchema.index({ user: 1, status: 1 });
