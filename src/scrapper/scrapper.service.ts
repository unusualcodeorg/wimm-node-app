import { Injectable } from '@nestjs/common';
import axios from 'axios';
import * as cheerio from 'cheerio';
import { ContentCategory } from '../content/schemas/content.schema';
import { MetaContentEntity } from './entities/meta-content.entity';

@Injectable()
export class ScrapperService {
  async scrape(url: string) {
    const response = await axios.get(url);
    const $ = cheerio.load(response.data);

    const title = $('title').text();
    const description = $('meta[name="description"]').attr('content') || '';
    const author = $('meta[name="author"]').attr('content') || '';
    const thumbnail = $('meta[property="og:image"]').attr('content') || '';
    const publisher = $('meta[property="og:site_name"]').attr('content') || '';

    const data: MetaContentEntity = new MetaContentEntity({
      category: ContentCategory.ARTICLE,
      title: title,
      subtitle: author,
      description: description,
      thumbnail: thumbnail,
      extra: url,
    });

    if (
      url.includes('https://youtu.be') ||
      url.includes('https://www.youtube.com/watch')
    ) {
      data.category = ContentCategory.YOUTUBE;
    }

    if (!data.subtitle) data.subtitle = publisher;
    if (!data.subtitle) data.subtitle = '';

    return data;
  }
}
