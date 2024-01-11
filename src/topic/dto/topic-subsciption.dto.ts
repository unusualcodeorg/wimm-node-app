import { IsBoolean } from 'class-validator';
import { Topic } from '../schemas/topic.schema';
import { TopicInfoDto } from './topic-info.dto';

export class TopicSubscriptionDto extends TopicInfoDto {
  @IsBoolean()
  subscribed: boolean;

  constructor(topic: Topic, subscribed: boolean) {
    super(topic);
    Object.assign(this, { subscribed: subscribed });
  }
}
