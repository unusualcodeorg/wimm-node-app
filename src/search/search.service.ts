import { Injectable } from '@nestjs/common';
import { SearchResultDto } from './dto/search-result.dto';
import { Category, Content } from '../content/schemas/content.schema';
import { Mentor } from '../mentor/schemas/mentor.schema';
import { Topic } from '../topic/schemas/topic.schema';
import { MentorService } from '../mentor/mentor.service';
import { TopicService } from '../topic/topic.service';
import { ContentsService } from '../content/contents.service';
import { SearchQueryDto } from './dto/search-query.dto';

@Injectable()
export class SearchService {
  constructor(
    private readonly mentorService: MentorService,
    private readonly topicService: TopicService,
    private readonly contentsService: ContentsService,
  ) {}

  async makeSearch(searchQueryDto: SearchQueryDto): Promise<SearchResultDto[]> {
    let data: SearchResultDto[] = [];
    if (searchQueryDto.filter) {
      switch (searchQueryDto.filter) {
        case Category.MENTOR_INFO: {
          data = await this.searchMentors(searchQueryDto.query);
          break;
        }
        case Category.TOPIC_INFO: {
          data = await this.searchTopics(searchQueryDto.query);
          break;
        }
      }
    } else {
      data = await this.search(searchQueryDto.query);
    }

    return data;
  }

  async searchMentors(query: string) {
    const searches = [this.mentorService.search(query, 10)];
    if (query.length >= 3)
      searches.push(this.mentorService.searchLike(query, 10));

    const results = await Promise.all(searches);
    const mentors: Mentor[] = [];

    for (const result of results) {
      for (const entry of result) {
        const found = mentors.find((m) => m._id.equals(entry._id));
        if (!found) mentors.push(entry);
      }
    }
    return mentors.map((mentor) => this.mentorToSearchDto(mentor));
  }

  async searchTopics(query: string) {
    const searches = [this.topicService.search(query, 10)];
    if (query.length >= 3)
      searches.push(this.topicService.searchLike(query, 10));

    const results = await Promise.all(searches);
    const topics: Topic[] = [];

    for (const result of results) {
      for (const entry of result) {
        const found = topics.find((t) => t._id.equals(entry._id));
        if (!found) topics.push(entry);
      }
    }
    return topics.map((t) => this.topicToSearchDto(t));
  }

  async search(query: string) {
    const searches: SearchResultDto[] = [];

    const contents = await this.contentsService.search(query, 5);
    const mentors = await this.mentorService.search(query, 5);
    const topics = await this.topicService.search(query, 5);

    searches.push(...contents.map((c) => this.contentToSearchDto(c)));
    searches.push(...mentors.map((m) => this.mentorToSearchDto(m)));
    searches.push(...topics.map((t) => this.topicToSearchDto(t)));

    if (query.length >= 3) {
      const similarContents = await this.contentsService.searchLike(query, 3);
      const similarMentors = await this.mentorService.searchLike(query, 3);
      const similarTopics = await this.topicService.searchLike(query, 3);

      searches.push(...similarContents.map((c) => this.contentToSearchDto(c)));
      searches.push(...similarMentors.map((m) => this.mentorToSearchDto(m)));
      searches.push(...similarTopics.map((t) => this.topicToSearchDto(t)));
    }

    const data: SearchResultDto[] = [];

    for (const entry of searches) {
      const found = data.find((s) => s.id.equals(entry.id));
      if (!found) data.push(entry);
    }

    return data;
  }

  mentorToSearchDto(mentor: Mentor) {
    return new SearchResultDto({
      id: mentor._id,
      title: mentor.name,
      category: Category.MENTOR_INFO,
      thumbnail: mentor.thumbnail,
      extra: mentor.occupation,
    });
  }

  topicToSearchDto(topic: Topic) {
    return new SearchResultDto({
      id: topic._id,
      title: topic.name,
      category: Category.TOPIC_INFO,
      thumbnail: topic.thumbnail,
      extra: topic.title,
    });
  }

  contentToSearchDto(content: Content) {
    return new SearchResultDto({
      id: content._id,
      title: content.title,
      category: content.category,
      thumbnail: content.thumbnail,
      extra: content.extra,
    });
  }
}
